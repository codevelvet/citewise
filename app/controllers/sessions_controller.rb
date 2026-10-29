class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  # Per IP. The store is Solid Cache in production, shared by every Puma worker.
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      # Read it first: starting the session resets the one that holds it.
      return_to = after_authentication_url
      start_new_session_for user
      redirect_to return_to
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
