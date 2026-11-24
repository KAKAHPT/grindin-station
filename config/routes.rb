# frozen_string_literal: true

Rails.application.routes.draw do
  # No direct uploads: every upload goes through a signed-in form that validates the file, while Active Storage's
  # own routes would let anyone write blobs to disk without an account. The app's routes are matched before the
  # engine's, so these two answer 404; the GET routes that serve blobs and variants stay Active Storage's.
  scope ActiveStorage.routes_prefix do
    not_found = ->(_env) { [404, { "content-type" => "text/plain" }, ["Not Found"]] }
    match "direct_uploads", to: not_found, via: :all
    put "disk/:encoded_token", to: not_found
  end

  # kamal-proxy health check: 200 when the app boots, 500 otherwise.
  get "up" => "rails/health#show", as: :rails_health_check
  # Content security policy violation reports (see config/initializers/content_security_policy.rb).
  post "csp-reports", to: "csp_reports#create", as: :csp_reports

  resource :session
  post "locale", to: "locales#update", as: :locale
  get "/auth/:provider/callback", to: "omniauth_callbacks#create", as: :omniauth_callback
  get "/auth/failure", to: "omniauth_callbacks#failure", as: :omniauth_failure
  resources :passwords, param: :token
  resources :registrations, only: %i[new create]
  resources :confirmations, only: %i[new create show], param: :token
  resource :account, only: %i[show update destroy]
  constraints(Features.constraint(:teams)) do
    resources :teams, only: :create
    resources :team_memberships, only: %i[create update destroy]
  end
  delete "/account/identities/:id" => "accounts#unlink_identity", as: :unlink_identity
  get "/p/:handle", to: "profiles#show", as: :profile, constraints: { handle: /[a-z0-9-]+/ }
  get "/privacy", to: "pages#privacy", as: :privacy
  # Modules that can be paused (config/features.yml): while one is off its routes do not match, so they answer 404.
  get "/fairness", to: "pages#fairness", as: :fairness, constraints: Features.constraint(:fairness)
  constraints(Features.constraint(:organizers)) do
    get "/organizers", to: "organizers#index", as: :organizers
    get "/o/:handle", to: "organizers#show", as: :organizer_profile, constraints: { handle: /[a-z0-9-]+/ }
  end
  constraints(Features.constraint(:feed)) do
    get "/feed", to: "posts#index", as: :feed
    post "/follows/:handle", to: "follows#create", as: :follow, constraints: { handle: /[a-z0-9-]+/ }
    delete "/follows/:handle", to: "follows#destroy", constraints: { handle: /[a-z0-9-]+/ }
    resources :posts, only: %i[create destroy], path: "feed/posts", as: :feed_posts do
      post :like, on: :member
      post :report, on: :member
    end
  end
  resources :notifications, only: :index do
    post :mark_all_read, on: :collection
  end

  resources :tournaments, only: %i[index show] do
    resources :rounds, only: :show

    resources :event_participants do
      collection do
        get "me"
        patch "check_in"
      end
    end
  end

  constraints(Features.constraint(:leagues)) do
    resources :leagues, only: %i[index show] do
      resources :rounds, only: :show

      resources :event_participants do
        collection do
          get "me"
        end
      end
    end
  end

  get "/t/:slug", to: "play/events#show", as: :play_event
  scope "/t/:slug", module: :play, as: :play do
    get "me", to: "tables#show"
    get "timer", to: "timers#show"
    get "pairings", to: "pairings#show"
    get "standings", to: "standings#show"
    get "standings/:participant_id", to: "standings#player", as: :standing_player
    resources :pods, only: [] do
      get "report/new", to: "reports#new"
      post "report", to: "reports#create"
      post "confirm", to: "reports#confirm"
      post "contest", to: "reports#contest"
    end
    resources :judge_calls, only: :create
  end

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "events/:slug/standings", to: "events#standings", as: :event_standings
      get "events/:slug/rounds", to: "events#rounds", as: :event_rounds
      get "events/:slug/info", to: "events#info", as: :event_info
    end
  end

  resources :events, only: %i[index]
  resources :circuits, only: %i[index show], constraints: Features.constraint(:circuits)
  get "/rankings", to: "rankings#show", as: :rankings, constraints: Features.constraint(:rankings)

  namespace :admin do
    root "dashboard#show"
    get "audit", to: "audit_events#index", as: :audit
    resources :errors, only: %i[index show], param: :fingerprint do
      post :resolve, on: :member
    end
    resources :events, only: %i[index] do
      patch :featured, on: :member
      patch :tier, on: :member
    end
    constraints(Features.constraint(:circuits)) do
      resources :circuits, only: %i[index] do
        patch :featured, on: :member
      end
    end
    constraints(Features.constraint(:feed)) do
      get "feed", to: "feed#index", as: :feed
      patch "feed/pause", to: "feed#pause", as: :pause_feed
      patch "feed/:id/keep", to: "feed#keep", as: :keep_feed
      delete "feed/:id/remove", to: "feed#remove", as: :remove_feed
    end
    constraints(Features.constraint(:rankings)) do
      get "invitational", to: "invitational#show", as: :invitational
      get "invitational/export.csv", to: "invitational#export", as: :invitational_export, format: false
    end
    # The approve/decline id is the waiting-list signup's, the revoke id the EventOrganizer's.
    resources :organizers, only: :index do
      member do
        patch :approve
        patch :decline
      end
    end
    patch "organizers/:id/revoke", to: "organizers#revoke", as: :revoke_organizer
  end

  namespace :organizer do
    root "tournaments#index"
    resource :about, only: %i[edit update], controller: "about", constraints: Features.constraint(:organizers)

    resources :tournaments do
      get :preview, on: :collection, to: "previews#new"
      member do
        get :preview, to: "previews#show"
        patch :reopen
        %w[players melee standings rounds pairings].each do |kind|
          get "export/#{kind}", to: "exports##{kind}", as: "export_#{kind}"
        end
        get "export/sheet", to: "exports#sheet", as: :export_sheet
      end
      resources :staff, only: %i[index create destroy]
      resources :judge_calls, only: %i[index] do
        member do
          patch :acknowledge
          patch :close
        end
      end
      resources :infractions, only: %i[new create]
      resources :event_participants do
        member do
          %i[check_in undo_check_in mark_paid mark_unpaid drop promote].each { |action| patch action }
        end
        get :search, on: :collection
        patch :check_in_all, on: :collection
        resources :infractions, only: %i[index destroy]
      end
      resources :rounds do
        member do
          get :print
          get :slips
        end
        resources :seatings, only: [] do
          patch :swap, on: :collection
        end
        resources :pods do
          patch :extra_time, on: :member
          resources :results do
            post :timeout, on: :collection
          end
          resources :infractions, only: %i[new create]
        end
      end
    end

    constraints(Features.constraint(:leagues)) do
      resources :leagues do
        member do
          %w[players melee standings rounds].each do |kind|
            get "export/#{kind}", to: "exports##{kind}", as: "export_#{kind}"
          end
        end
        resources :infractions, only: %i[new create]
        resources :event_participants do
          resources :infractions, only: %i[index destroy]
        end
        resources :rounds do
          member do
            get :print
            get :slips
          end
          resources :seatings, only: [] do
            patch :swap, on: :collection
          end
          resources :pods do
            resources :results
            resources :infractions, only: %i[new create]
          end
        end
        post :create_pickup_pod, on: :member
      end
    end

    constraints(Features.constraint(:circuits)) do
      resources :circuits do
        resources :tournaments, only: %i[new create]
      end
    end
  end

  post "waitlist", to: "waitlist_signups#create", as: :waitlist_signups

  root "pages#home"
end
