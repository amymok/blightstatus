FactoryGirl.define do
  factory :account do
    sequence(:email)        { |n| "user-#{n}@nola.com" }
    password                "dummydata"
    password_confirmation   "dummydata"
  end

  factory :address do
    geopin            { 41125604 }
    address_id        { 1 + rand(20000) } #{ 85102061 }
    address_long      { "1019 CHARBONNET ST" }
    street_name       { "CHARBONNET" }
    street_type       { "ST" }
    point             {"POINT (-90.04223467290467 29.975021724674335)"}
  end

  factory :case do
    case_number       { "CEHB-" + rand(1000).to_s()}
  end

  factory :demolition do
    demo_number         {"DEMO-" + rand(1000).to_s()}
    date_completed      { DateTime.new(rand(1000))}
    date_started        { DateTime.new(rand(1000))}
    #date_started      {Time.now - 2.days}
    #date_completed    {Time.now - 1.days}
  end

  factory :foreclosure do
    sale_date {DateTime.now - 2.days}
    cdc_case_number {"CDC-" + rand(1000).to_s()}
  end

  factory :hearing do
    hearing_date      { DateTime.new(rand(1000)) }
  end

  factory :inspection do
    inspection_type   { "Violation Posted No WIP" }
    inspection_date   { DateTime.new(rand(1000)) }
    scheduled_date    { DateTime.new(rand(1000)) }
  end

  factory :inspector do
    name              {"In Spector"}
  end

  factory :judgement do
    judgement_date    { Time.now }
    status            {"guilty"}
  end

  factory :complaint do
  end

  factory :maintenance do
  end

  factory :neighborhood do
    name       { "HOOD " + rand(1000).to_s()}
  end

  factory :notification do
    #are there any fields to require?
    notified   { DateTime.new(rand(1000)) }
  end

  factory :reset do
    reset_date {DateTime.new(rand(1000))}
  end

  factory :street do
    #name       { "CHARBONNET" }
  end

  factory :subscription do
    account
    address
  end
end
