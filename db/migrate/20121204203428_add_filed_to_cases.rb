class AddFiledToCases < ActiveRecord::Migration
  def change
  	add_column :cases, :filed, :datetime
  end
end
