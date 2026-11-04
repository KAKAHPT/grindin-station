# frozen_string_literal: true

class AddOneOpenJudgeCallPerPodIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :judge_calls, :pod_id, unique: true, where: "status = 'open' AND pod_id IS NOT NULL",
                                     name: "index_judge_calls_one_open_per_pod"
  end
end
