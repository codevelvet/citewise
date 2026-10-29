class QuestionsController < ApplicationController
  LIMITS = Rails.configuration.x.ask_page

  # Per-user limits keep one account from filling the ask queue. The daily cap protects the
  # API budget across every account. Rate limits apply to creating questions only.
  rate_limit to: LIMITS[:per_minute], within: 1.minute, name: "minute", only: :create, by: -> { Current.user.id },
             store: LIMITS[:rate_limit_store] || cache_store, with: -> { too_many_questions(:user) }
  rate_limit to: LIMITS[:per_hour], within: 1.hour, name: "hour", only: :create, by: -> { Current.user.id },
             store: LIMITS[:rate_limit_store] || cache_store, with: -> { too_many_questions(:user) }
  before_action :enforce_daily_cap, only: :create

  # Questions can be personal, and a shared answer page could pass off a coaxed answer as
  # Citewise's, so only the visitor who asked can see one. Everyone else gets a 404.
  before_action :set_question, only: %i[show answer]

  def new
    # Example questions and "Ask again" links pre-fill the box; a GET never asks anything.
    @question = Question.new(text: params[:text].to_s.first(Question::MAX_TEXT_LENGTH))
  end

  def create
    @question = Question.new(text: params.expect(question: [ :text ])[:text])

    if @question.save
      # The cookie session is encrypted, so visitors can't add other IDs. Capped to keep it small.
      session[:question_ids] = [ *session[:question_ids], @question.id ].last(LIMITS[:per_day])
      AskJob.perform_later(@question)
      redirect_to @question
    else
      render :new, status: :unprocessable_content
    end
  end

  # HTML only. Turbo follows the create redirect asking for streams first, so a stream
  # format here would answer that navigation instead of rendering the page.
  def show
  end

  # Fetched once the page's stream subscription is confirmed, in case the answer was
  # broadcast before then. Nothing to replace while it's still pending.
  def answer
    respond_to do |format|
      format.turbo_stream { head :no_content if @question.pending? }
    end
  end

  private
    # The same page whether or not the question exists, so it doesn't confirm that one does.
    # The session cookie ends when the browser closes, so the asker can land here too.
    def set_question
      @question = Question.find_by(id: params[:id]) if Array(session[:question_ids]).include?(params[:id].to_i)
      return if @question

      # formats: :html, because Turbo's Accept header lists streams first.
      action_name == "show" ? render(:unavailable, status: :not_found, formats: :html) : head(:not_found)
    end

    def enforce_daily_cap
      too_many_questions(:everyone) if Question.where(created_at: 24.hours.ago..).count >= LIMITS[:per_day]
    end

    def too_many_questions(limit)
      render :too_many_requests, status: :too_many_requests, locals: { limit: limit }
    end
end
