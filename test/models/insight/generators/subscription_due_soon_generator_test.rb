require "test_helper"

class Insight::Generators::SubscriptionDueSoonGeneratorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @subscription = recurring_transactions(:netflix_subscription)
    @subscription.update!(bill_type: "subscription")
    @renewal = @subscription.recurring_occurrences.create!(
      family: @family,
      original_due_on: 3.days.from_now.to_date,
      due_on: 3.days.from_now.to_date,
      currency: @subscription.currency
    )
    @generator = Insight::Generators::SubscriptionDueSoonGenerator.new(@family)
  end

  test "generates a medium-priority reminder for a subscription due within the horizon" do
    insights = @generator.generate

    assert_equal 1, insights.length
    insight = insights.first
    assert_equal "subscription_due_reminder", insight.insight_type
    assert_equal "medium", insight.priority
    assert_equal "subscription_due_reminder:#{@renewal.id}", insight.dedup_key
    assert_equal @renewal.due_on.iso8601, insight.metadata[:due_on]
    assert_equal @subscription.id, insight.metadata[:recurring_transaction_id]
    assert_equal @subscription.account_id, insight.metadata[:account_id]
  end

  test "ignores renewals beyond the horizon" do
    @renewal.update!(due_on: 20.days.from_now.to_date, original_due_on: 20.days.from_now.to_date)

    assert_empty @generator.generate
  end

  test "ignores occurrences that are not subscriptions" do
    @subscription.update!(bill_type: "bill")

    assert_empty @generator.generate
  end

  test "generates nothing when recurring transactions are disabled" do
    @family.update!(recurring_transactions_disabled: true)

    assert_empty @generator.generate
  end

  test "reports only the nearest open occurrence per series" do
    @subscription.recurring_occurrences.create!(
      family: @family,
      original_due_on: 6.days.from_now.to_date,
      due_on: 6.days.from_now.to_date,
      currency: @subscription.currency
    )

    insights = @generator.generate

    assert_equal 1, insights.length
    assert_equal "subscription_due_reminder:#{@renewal.id}", insights.first.dedup_key
  end
end
