# Signals subscription renewals landing inside the reminder window. The charge
# is scheduled either way -- BillNotCoveredGenerator owns the "will the balance
# cover it" question -- so this card is a heads-up about money leaving soon,
# not a warning. One card per occurrence: paying or snoozing it retires the
# reminder, and the next cycle's occurrence opens a fresh one.
class Insight::Generators::SubscriptionDueSoonGenerator < Insight::Generator
  produces "subscription_due_reminder"

  HORIZON_DAYS = 7
  MAX_INSIGHTS = 5

  def generate
    # The schedule is the whole subject here, as in SubscriptionAuditGenerator:
    # with recurring transactions off, occurrences stop being generated and
    # what is left is a stale schedule.
    return [] if family.recurring_transactions_disabled?

    due_subscriptions.first(MAX_INSIGHTS).map { |occurrence| build_reminder(occurrence) }
  end

  private
    # Outbound subscription occurrences due within the horizon. Past-due ones
    # belong to SubscriptionAuditGenerator; bills without an explicit type stay
    # with BillNotCoveredGenerator. A snoozed renewal counts on the date it was
    # snoozed to, so the reminder follows the user's own postponement.
    def due_subscriptions
      family.recurring_occurrences
        .open_status
        .joins(:recurring_transaction)
        .where(recurring_transactions: { status: :active, destination_account_id: nil, bill_type: "subscription" })
        .merge(shared_recurring_transactions)
        .where("recurring_transactions.amount > 0")
        .where("#{RecurringOccurrence::EFFECTIVE_DUE_ON_SQL} BETWEEN ? AND ?", Date.current, Date.current + HORIZON_DAYS)
        .includes(recurring_transaction: [ :merchant ])
        .to_a
        .group_by(&:recurring_transaction_id)
        .values
        .map { |group| group.min_by { |occurrence| [ occurrence.effective_due_on, occurrence.id ] } }
        .sort_by(&:effective_due_on)
    end

    def build_reminder(occurrence)
      recurring = occurrence.recurring_transaction
      name = recurring.merchant&.name.presence || recurring.name
      amount = Money.new(occurrence.resolved_expected_amount, occurrence.currency).format
      due_on = occurrence.effective_due_on

      build_insight(
        insight_type: "subscription_due_reminder",
        priority: "medium",
        title: I18n.t("insights.titles.subscription_due_reminder", name: name, due_on: I18n.l(due_on)),
        template_key: "subscription_due_reminder",
        facts: {
          name: name,
          amount: amount,
          due_on: I18n.l(due_on)
        },
        # due_on moves only when the user snoozes -- a new situation worth
        # resurfacing. The amount and the named series are stable, so a
        # dismissed card does not resurrect on nightly number drift.
        metadata: {
          recurring_transaction_id: recurring.id,
          account_id: recurring.account_id,
          amount: round(occurrence.resolved_expected_amount, 2),
          due_on: due_on.iso8601
        }.compact,
        dedup_key: "subscription_due_reminder:#{occurrence.id}"
      )
    end
end
