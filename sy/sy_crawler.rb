require 'rubygems'
require 'yaml'
require 'anemone'
require 'nokogiri'
require 'harmony'

class VisualizationParser

  attr_accessor :language
  attr_accessor :subtitles
  attr_accessor :online_link
  attr_accessor :download_link

  def initialize node
    @language = node[1].content
    @subtitles = node[2].content

    crypted_online_link = node[0].xpath('.//a')[0].attribute('href').value
    # Request online link
    doc = Nokogiri::HTML(Harmony::Page.fetch(crypted_online_link).to_html)
    @online_link = doc.xpath('//span/b/a')[0].attribute('href').content

    crypted_download_link = doc.xpath('//h3/a')[1].attribute('href').content unless doc.xpath('//h3/a').empty?
    # Request donwload link
    doc = Nokogiri::HTML(Harmony::Page.fetch(crypted_download_link).to_html)
    @download_link = doc.xpath('//h3/a')[0].attribute('href').content
  end

  def to_yml
    {
       :language => @language,
       :subtitles => @subtitles,
       :online_link => @online_link,
       :download_link => @download_link
    }
  end

end

class EpisodeParser

  attr_accessor :title
  attr_accessor :visualizations

  def initialize(doc)
    @title = doc.xpath('//h1')[-1].content
    @visualizations = []

    table_node = doc.xpath('//table').first
    if table_node
      @visualizations = table_node.xpath('tr')[1..-1].collect do |tr|
        VisualizationParser.new(tr.xpath('td/div/span')) rescue nil
      end.compact
    end
  end

  def to_yml
    {
      :title => @title,
      :visualizations => @visualizations.collect { |v| v.to_yml }
    }
  end

end

# Start url
URL = "http://www.seriesyonkis.com"
# User agent for the crawler
UA = "Mozilla/5.0 (Windows; U; MSIE 7.0; Windows NT 6.0; es-ES)"
# Patterns
SERIE_PATTERN = "#{URL}\/serie\/(.*)\/"
EPISODE_PATTERN = "#{URL}\/capitulo\/.*\/(.*)\/\\d+\/"

# Starts goear crawling process
Anemone.crawl(URL, :user_agent => UA) do |anemone|

  #TODO: Group episodes by series

  # Episodes list
  episodes = []

  # Focus crawler to follow series or episodes urls
  anemone.focus_crawl do |page|
    page.links.select { |link| link.to_s =~ /#{SERIE_PATTERN}|#{EPISODE_PATTERN}/ }
  end

  # Parses episodes urls
  anemone.on_pages_like(/#{EPISODE_PATTERN}/) do |page|
    episodes << EpisodeParser.new(page.doc)
  end

  # Dump information
  anemone.after_crawl do |page|
    File.open("data.yml", "w") { |f| YAML.dump(episodes.collect { |e| e.to_yml }, f) }
  end

end
