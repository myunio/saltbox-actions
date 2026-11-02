ActiveRecord::Schema.define(version: 1) do
  create_table :events, force: true do |t|
    t.integer :org_id, null: false
    t.string :title, null: false, limit: 120
    t.date :starts_on
    t.integer :capacity
    t.decimal :price, precision: 8, scale: 2
    t.boolean :featured, null: false, default: false
    t.datetime :doors_open_at
    t.string :status, null: false, default: "draft"
    t.text :notes
    t.integer :parent_id
    t.timestamps
  end

  create_table :billing_invoices, force: true do |t|
    t.integer :org_id, null: false
    t.string :number, null: false
    t.timestamps
  end

  create_table :versions, force: true do |t|
    t.string :item_type, null: false
    t.string :item_id, null: false
    t.string :event, null: false
    t.string :whodunnit
    t.text :object
    t.string :agent
    t.string :surface
    t.string :invocation_id
    t.datetime :created_at
  end
end
