# frozen_string_literal: true

# Slugs become unique: duplicates (same name) keep the oldest as is and get "-2", "-3", … in creation
# order, skipping any suffix already in use. Plain SQL, no model callbacks.
class AddUniqueIndexToEventsSlug < ActiveRecord::Migration[8.1]
  def up
    duplicated = select_values("SELECT slug FROM events GROUP BY slug HAVING COUNT(*) > 1")
    duplicated.each { |slug| suffix_duplicates(slug) }

    add_index :events, :slug, unique: true
  end

  def down
    remove_index :events, :slug
  end

  private

  def suffix_duplicates(slug)
    ids = select_values("SELECT id FROM events WHERE slug = #{quote(slug)} ORDER BY created_at, id").drop(1)
    n = 2
    ids.each do |id|
      n += 1 while select_value("SELECT 1 FROM events WHERE slug = #{quote("#{slug}-#{n}")}")
      execute("UPDATE events SET slug = #{quote("#{slug}-#{n}")} WHERE id = #{quote(id)}")
      n += 1
    end
  end

  def quote(value)
    connection.quote(value)
  end
end
