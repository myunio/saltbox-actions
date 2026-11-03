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

  create_table :orgs, force: true do |t|
    t.timestamps
  end

  # As `rails g actions:approvals` writes it, with a tenant.
  create_table :saltbox_action_approvals, force: true do |t|
    t.integer :tenant_id, null: false
    t.integer :user_id, null: false
    t.integer :connection_id
    t.string :surface, null: false
    t.string :agent_name
    t.string :action_name, null: false
    t.string :confirms, null: false
    t.json :arguments, null: false
    t.string :arguments_digest, null: false
    t.datetime :approved_at
    t.datetime :used_at
    t.datetime :expires_at, null: false
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
