# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "organizer", preload: "organizer"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Vendored copy (vendor/javascript) so no page asks a CDN for scripts. Flowbite is imported only by
# the organizer entry point.
pin "flowbite", preload: "organizer" # flowbite@4.0.1 dist/flowbite.turbo.min.js
