class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :force_utf8

  private

  def force_utf8
    # on ne touche qu'au HTML
    if response.content_type.nil? || response.content_type.start_with?("text/html")
      response.headers["Content-Type"] = "text/html; charset=utf-8"
    end
  end
end
