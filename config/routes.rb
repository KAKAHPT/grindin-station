# frozen_string_literal: true

Rails.application.routes.draw do
  # kamal-proxy health check: 200 when the app boots, 500 otherwise.
  get "up" => "rails/health#show", as: :rails_health_check
  # Content security policy violation reports (see config/initializers/content_security_policy.rb).
  post "csp-reports", to: "csp_reports#create", as: :csp_reports

  resource :session
  get "/auth/:provider/callback", to: "omniauth_callbacks#create", as: :omniauth_callback
  get "/auth/failure", to: "omniauth_callbacks#failure", as: :omniauth_failure
  resources :passwords, param: :token
  resources :registrations, only: %i[new create]
  resource :account, only: %i[show update destroy]
  delete "/account/identities/:id" => "accounts#unlink_identity", as: :unlink_identity
  get "/p/:handle", to: "profiles#show", as: :profile, constraints: { handle: /[a-z0-9-]+/ }
  resources :notifications, only: :index do
    post :mark_all_read, on: :collection
  end

  resources :tournaments, only: %i[index show] do
    resources :rounds, only: :show

    resources :event_participants do
      collection do
        get "me"
      end
    end
  end

  resources :leagues, only: %i[index show] do
    resources :rounds, only: :show

    resources :event_participants do
      collection do
        get "me"
      end
    end
  end

  get "/t/:slug", to: "play/events#show", as: :play_event
  scope "/t/:slug", module: :play, as: :play do
    get "me", to: "tables#show"
    get "timer", to: "timers#show"
    get "pairings", to: "pairings#show"
    get "standings", to: "standings#show"
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
  resources :circuits, only: %i[index show]

  namespace :organizer do
    root "tournaments#index"

    resources :tournaments do
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

    resources :leagues do
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

    resources :circuits do
      resources :tournaments, only: %i[new create]
    end
  end

  root "events#index"
end
