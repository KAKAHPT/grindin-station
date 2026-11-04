# frozen_string_literal: true

# POST /waitlist from the landing card. The answer is the same whether or not the e-mail was already on the list.
class WaitlistSignupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create,
             with: -> { respond(WaitlistSignup.new, :too_many_requests, state: :limited) }

  def create
    signup = WaitlistSignup.new(params.expect(waitlist_signup: %i[name email]))
    signup.save
    signup.errors.delete(:email, :taken)
    signup.errors.empty? ? respond(signup, :ok, state: :done) : respond(signup, :unprocessable_content)
  rescue ActiveRecord::RecordNotUnique
    respond(signup, :ok, state: :done)
  end

  private

  def respond(signup, status, state: nil)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("waitlist", partial: "pages/waitlist",
                                                              locals: { signup: signup, state: state }),
               status: status
      end
      format.html { respond_without_turbo(state, status) }
    end
  end

  def respond_without_turbo(state, status)
    message = t("landing.waitlist.#{state || :invalid}")
    return render(plain: message, status: status) if state == :limited

    redirect_to root_path(locale: params[:locale], anchor: "waitlist"),
                (state == :done ? :notice : :alert) => message
  end
end
