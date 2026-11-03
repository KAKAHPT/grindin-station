# frozen_string_literal: true

# Results of a closed round are never overwritten: a correction adds fresh rows and points the
# old ones at them. Only rows with no superseded_by are current, so uniqueness becomes partial.
class AddSupersedingToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :superseded_by_id, :uuid
    add_column :results, :recorded_by_user_id, :uuid
    add_index :results, :superseded_by_id
    add_index :results, :recorded_by_user_id
    # Deferred so a correction can point the old row at the new one before inserting it.
    add_foreign_key :results, :results, column: :superseded_by_id, on_delete: :nullify, deferrable: :deferred
    add_foreign_key :results, :users, column: :recorded_by_user_id, on_delete: :nullify

    remove_index :results, %i[event_participant_id round_id], unique: true,
                                                              name: "index_results_on_event_participant_id_and_round_id"
    add_index :results, %i[event_participant_id round_id], unique: true, where: "superseded_by_id IS NULL",
                                                           name: "index_results_current_on_participant_and_round"
  end
end
