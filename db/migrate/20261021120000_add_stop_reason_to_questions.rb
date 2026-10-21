class AddStopReasonToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :stop_reason, :string
  end
end
