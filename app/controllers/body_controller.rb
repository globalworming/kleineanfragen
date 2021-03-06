class BodyController < ApplicationController
  before_filter :find_body

  def show
    @terms = Paper.where(body: @body).group(:legislative_term).count.to_a.sort.reverse
    @scraper_result = @body.scraper_results.where.not(stopped_at: nil).order(stopped_at: :desc).first
    @latest_paper = @body.papers.where.not(published_at: nil).order(published_at: :desc).first
  end

  def feed
    @papers = @body.papers
              .where.not(published_at: nil)
              .order(published_at: :desc, reference: :desc)
              .page params[:page]
    fresh_when last_modified: @papers.maximum(:updated_at), public: true
  end

  def subscribe
    @subscription = Subscription.new
    @subscription.subtype = :body
    @subscription.query = @body.state
  end

  private

  def find_body
    @body = Body.friendly.find params[:body]
  end
end
