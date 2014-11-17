class FetchPapersBayernJob < FetchPapersJob

  @state = 'BY'
  @scraper = BayernLandtagScraper

  def perform(legislative_term = 17)
    setup(legislative_term)

    import_new_papers
    load_paper_details
    download_papers
    extract_text_from_papers
    count_page_numbers
    extract_people_names
  end

  def import_all(legislative_term = 17)
    setup(legislative_term)
    import_all_papers
  end

  def import_paper(item)
    item.delete :full_reference
    unless Paper.where(body: @body, legislative_term: item[:legislative_term], reference: item[:reference]).exists?
      Rails.logger.debug "[import_paper]  New Paper: [#{item[:reference]}] \"#{item[:title]}\""
      paper = Paper.new(item)
      paper.body = @body
      paper.save
      return paper
    end
    false
  end

  def load_paper_details
    @papers = Paper.find_by_sql(
      ["SELECT p.* FROM papers p LEFT OUTER JOIN paper_originators o ON (o.paper_id = p.id) WHERE p.body_id = ? AND o.id IS NULL", @body.id])

    @papers.each do |paper|
      Rails.logger.info "Loading details for Paper [#{paper.reference}]"
      detail = BayernLandtagScraper::Detail.new(paper.legislative_term, paper.reference).scrape
      org = Organization.where('lower(name) = ?', detail[:originator].mb_chars.downcase.to_s).first_or_create(name: detail[:originator])
      Rails.logger.info "- Originator: #{org.name}"
      unless paper.originator_organizations.include? org
        paper.originator_organizations << org
        paper.save
      end
    end
  end

  # FIXME: cleanup
  def extract_people_names
    @papers = Paper.find_by_sql(
      ["SELECT p.* FROM papers p LEFT OUTER JOIN paper_originators o ON (o.paper_id = p.id AND o.originator_type = 'Person') WHERE p.body_id = ? AND o.id IS NULL", @body.id])

    @papers.each do |paper|
      get_or_download_pdf(paper)
      originators = BayernPDFExtractor.new(paper).extract
      next if originators.nil?

      if !originators[:party].empty?
        # write org
        party = originators[:party]
        org = Organization.where('lower(name) = ?', party.mb_chars.downcase.to_s).first_or_create(name: party)
        unless paper.originator_organizations.include? org
          paper.originator_organizations << org
          paper.save
        end
      end

      if !originators[:people].empty?
        # write people
        originators[:people].each do |name|
          person = Person.where('lower(name) = ?', name.mb_chars.downcase.to_s).first_or_create(name: name)
          unless paper.originator_people.include? person
            paper.originator_people << person
            paper.save
          end
        end
      end
    end
  end
end