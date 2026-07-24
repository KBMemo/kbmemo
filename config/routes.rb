Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # AsciiDoc image::/images/filename[] → Propshaft（app/assets/images 等）
  get "images/*filename", to: "app_images#show", as: :app_image, format: false

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  post "csp_reports", to: "csp_reports#create"

  get "themes/studio", to: "themes#studio", as: :theme_studio
  resource :theme, only: %i[show update], controller: "themes", defaults: { format: :json }

  root "dashboard#show"

  get "help", to: "help#show", as: :help
  get "help/:memo_slug", to: "help#show", as: :help_memo

  resource :agent_chat, only: %i[show create destroy], controller: "agent_chats" do
    get :nyoy_tools
    get :memo_references
    post :upload_image
    get "image_generations/:id", action: :image_generation_status, as: :image_generation
    post "image_generations/:id/refine", action: :refine_image_generation, as: :refine_image_generation
  end

  resource :chat_server, only: %i[show update], controller: "chat_servers" do
    get :model_options
    post :health_check
    post :list_models
  end

  resource :nyoy_mcp, only: %i[show update], controller: "nyoy_mcp_settings" do
    post :test_connection
  end

  resource :profile, only: %i[edit update] do
    post :api_token, action: :create_api_token
    delete :api_token, action: :destroy_api_token
    post :web_clip_tokens, action: :create_web_clip_token
    delete "web_clip_tokens/:token_id", action: :destroy_web_clip_token, as: :web_clip_token
    post :tsuzura_api_token, action: :create_tsuzura_api_token
    delete :tsuzura_api_token, action: :destroy_tsuzura_api_token
  end

  get "google_calendar/connect", to: "google_calendar_connections#connect", as: :google_calendar_connect
  get "google_calendar/callback", to: "google_calendar_connections#callback", as: :google_calendar_callback
  post "google_calendar/sync", to: "google_calendar_connections#sync", as: :google_calendar_sync
  delete "google_calendar/data", to: "google_calendar_connections#clear_data", as: :google_calendar_clear_data
  delete "google_calendar/disconnect", to: "google_calendar_connections#disconnect", as: :google_calendar_disconnect

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  namespace :admin do
    resources :accounts, only: %i[index show edit update]
    root to: "accounts#index"
  end

  resources :memo_directories, except: [ :show ]
  resources :memo_templates, except: :show

  resources :tags, only: %i[index edit update destroy] do
    collection do
      get "merge", action: :merge_form
      post "merge", action: :merge
    end
  end

  resources :boards do
    member do
      patch :move_card
      get :available_memos
    end

    resources :board_columns, only: %i[update], path: "columns" do
      member do
        post :swap
      end
    end

    resources :board_cards, only: %i[create destroy], path: "cards" do
      member do
        patch :schedule
      end
    end
  end

  resources :notebooks do
    member do
      patch :publish
      patch :unpublish
      patch :reorder_memos
      get :available_memos
    end

    resources :notebook_memos, only: %i[create destroy], path: "memos" do
      collection do
        post :create_blank
      end
    end
  end

  resources :memos do
    collection do
      get :wiki_completions
      get :wiki_link_labels
      get :sidebar_memo_list
      get :manage
      patch :bulk_add_tags
      patch :bulk_remove_tags
      patch :bulk_move_directory
      post :bulk_add_to_notebook
    end

    member do
      post :ai_chat, to: "memo_ai_chats#create"
      post :metadata_suggestions, to: "memo_metadata_suggestions#create"
      patch :draft
      patch :commit
      patch :revert_draft
      patch :checklist_toggle
      patch :update_directory
      patch :update_tags
      post :render_diagram
      get "svg_sources/:index/edit", to: "memo_svg_sources#edit", as: :edit_svg_source, constraints: { index: /\d+/ }
      patch "svg_sources/:index", to: "memo_svg_sources#update", as: :svg_source, constraints: { index: /\d+/ }
      post "assets", to: "memo_assets#create", as: :assets
      get "assets/*filename/view", to: "memo_assets#view", as: :asset_view, format: false
      get "assets/*filename", to: "memo_assets#show", as: :asset, format: false
      delete "assets", to: "memo_assets#destroy", as: :destroy_asset
    end

    resources :diagrams, only: %i[new create edit update], controller: "memo_diagrams",
      param: :diagram_key,
      constraints: { diagram_key: /[^\/]+/ } do
      member do
        post :preview
        get :view
        get :source
      end
    end
  end

  namespace :api do
    match "clips", to: "clips#options", via: :options
    resources :clips, only: :create

    namespace :v1 do
      resource :me, only: :show, controller: "me"
      resources :memos, only: %i[index show create update destroy], param: :memo_ref do
        collection do
          get :export, to: "memos/export#index"
          get "export/deletions", to: "memos/export#deletions"
        end
      end
    end
  end

  namespace :internal do
    get "tsuzura/albums", to: "tsuzura#albums", as: :tsuzura_albums
    get "tsuzura/albums/:id", to: "tsuzura#album", as: :tsuzura_album
    post "tsuzura/sign_urls", to: "tsuzura#sign_urls", as: :tsuzura_sign_urls
  end
end
