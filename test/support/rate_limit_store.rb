# frozen_string_literal: true

# The test cache is a null store, so rate limits never trip; this counts in memory for one block.
module RateLimitStore
  def with_memory_rate_limit_store
    store = ApplicationController.cache_store
    memory = ActiveSupport::Cache::MemoryStore.new
    store.define_singleton_method(:increment) { |*args, **options| memory.increment(*args, **options) }
    yield
  ensure
    store.singleton_class.remove_method(:increment)
  end
end
