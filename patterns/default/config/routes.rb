ActionController::Routing::Routes.draw do |map|
  map.resource :account, :except => :destroy
  map.resources :password_resets, :only => [:new, :create, :edit, :update]
  map.resources :users
  map.resource :user_session, :only => [:new, :create, :destroy]
  map.login 'login', :controller => "user_sessions", :action => "new"
  map.logout 'logout', :controller => "user_sessions", :action => "destroy"
#{activation_routes}
  map.register 'register', :controller => "accounts", :action => "new"
  map.root :controller => "pages", :action => "home"
  map.pages 'pages/:action', :controller => "pages"
end
