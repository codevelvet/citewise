module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      # Only page navigations: returning to a stream or form endpoint would show a blank page or an error.
      # html? alone also matches Turbo Streams, whose type is text/vnd.turbo-stream.html.
      session[:return_to_after_authenticating] = request.url if request.get? && request.format.html? && !request.format.turbo_stream?
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # Both reset the Rails session, so question_ids and the rest never carry over from
    # one signed-in person to the next on a shared browser.
    def start_new_session_for(user)
      reset_session
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
      reset_session
    end
end
