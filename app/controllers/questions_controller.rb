class QuestionsController < ApplicationController
  LIMITS = Rails.configuration.x.ask_page

  # Per-IP limits keep one visitor from filling the ask queue. The daily cap protects the
  # API budget even if they're evaded. Rate limits apply to creating questions only.
  rate_limit to: LIMITS[:per_minute], within: 1.minute, name: "minute", only: :create,
             store: LIMITS[:rate_limit_store] || cache_store, with: -> { too_many_questions(:visitor) }
  rate_limit to: LIMITS[:per_hour], within: 1.hour, name: "hour", only: :create,
             store: LIMITS[:rate_limit_store] || cache_store, with: -> { too_many_questions(:visitor) }
  before_action :enforce_daily_cap, only: :create

  def new
    # Example questions and "Ask again" links pre-fill the box; a GET never asks anything.
    @question = Question.new(text: params[:text].to_s.first(Question::MAX_TEXT_LENGTH))
  end

  def create
    @question = Question.new(text: params.expect(question: [ :text ])[:text])

    if @question.save
      AskJob.perform_later(@question)
      redirect_to @question
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @question = Question.find(params[:id])

    respond_to do |format|
      format.html
      # Fetched once the page's stream subscription is confirmed, in case the answer was
      # broadcast before then. Nothing to replace while it's still pending.
      format.turbo_stream { head :no_content if @question.pending? }
    end
  end

  private
    def enforce_daily_cap
      too_many_questions(:everyone) if Question.where(created_at: 24.hours.ago..).count >= LIMITS[:per_day]
    end

    def too_many_questions(limit)
      render :too_many_requests, status: :too_many_requests, locals: { limit: limit }
    end
end
