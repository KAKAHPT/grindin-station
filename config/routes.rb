# frozen_string_literal: true

Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :registrations, only: %i[new create]

  resources :tournaments, only: %i[index show] do
    resources :rounds do
      resources :pods
    end

    resources :event_participants do
      collection do
        get "me"
      end
    end
  end

  resources :leagues, only: %i[index show] do
    resources :rounds do
      resources :pods
    end

    resources :event_participants do
      collection do
        get "me"
      end
    end
  end

  scope "/t/:slug", module: :play, as: :play do
    get "me", to: "tables#show"
    get "timer", to: "timers#show"
    resources :pods, only: [] do
      get "report/new", to: "reports#new"
      post "report", to: "reports#create"
      post "confirm", to: "reports#confirm"
      post "contest", to: "reports#contest"
    end
    resources :judge_calls, only: :create
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
