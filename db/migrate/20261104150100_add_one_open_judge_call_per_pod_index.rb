# frozen_string_literal: true

class AddOneOpenJudgeCallPerPodIndex < ActiveRecord::Migration[8.1]
  # Before the unique index: the oldest open call of a pod stays open, the others are closed (not deleted,
  # they are the audit of the call); every closed row is printed.
  def up
    close_duplicate_open_calls
    add_index :judge_calls, :pod_id, unique: true, where: "status = 'open' AND pod_id IS NOT NULL",
                                     name: "index_judge_calls_one_open_per_pod"
  end

  def down
    remove_index :judge_calls, name: "index_judge_calls_one_open_per_pod"
  end

  private

  def close_duplicate_open_calls
    duplicates = select_values(<<~SQL.squish)
      SELECT id FROM (
        SELECT id, row_number() OVER (PARTITION BY pod_id ORDER BY created_at, id) AS n
        FROM judge_calls WHERE status = 'open' AND pod_id IS NOT NULL
      ) ranked WHERE n > 1
    SQL
    duplicates.each do |id|
      say "judge_calls: closed duplicate open call #{id}"
      execute "UPDATE judge_calls SET status = 'closed', closed_at = now() WHERE id = #{quote(id)}"
    end
  end
end
