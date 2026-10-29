Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # The ask page. Checked on every request, so these routes 404 while config.x.ask_page[:enabled] is off.
  constraints ->(_request) { Rails.configuration.x.ask_page[:enabled] } do
    root "questions#new"
    resources :questions, only: %i[new create show] do
      get :answer, on: :member
    end
  end
end
