require 'rubygems'
require 'yaml'
require 'anemone'
require 'nokogiri'
require 'harmony'

class Visualization

  attr_accessor :language
  attr_accessor :subtitles
  attr_accessor :online_link
  attr_accessor :download_link

  # TODO: Improve crypted links extraction
  def initialize node
    @language = node[1].content
    @subtitles = node[2].content

    crypted_online_link = node[0].xpath('.//a')[0].attribute('href').content
    # Request online link
    doc = Nokogiri::HTML(Harmony::Page.fetch(crypted_online_link).to_html)
    @online_link = doc.xpath('//span/b/a')[0].attribute('href').content

=begin
    download_node = doc.xpath('//h3/a')[1]
    if download_node
      crypted_download_link = download_node.attribute('href').content
      # Request donwload link
      doc = Nokogiri::HTML(Harmony::Page.fetch(crypted_download_link).to_html)
      @download_link = doc.xpath('//h3/a')[0].attribute('href').content
    end
=end
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

class Episode

  attr_accessor :title
  attr_accessor :serie
  attr_accessor :visualizations

  def initialize doc
    @title = doc.xpath('//h1')[-1].content
    @serie = doc.xpath('//h2/a')[0].content
    @visualizations = []

    table_node = doc.xpath('//table')[0]
    if table_node
      @visualizations = table_node.xpath('tr')[1..-1].collect do |tr|
        Visualization.new(tr.xpath('td/div/span')) rescue nil
      end.compact
    end
  end

  def to_yml
    {
      :visualizations => @visualizations.collect { |v| v.to_yml },
      :title => @title
    }
  end

end

class Serie

  attr_accessor :name
  attr_accessor :episodes

  def initialize doc
    @name = doc.xpath('//h1/a')[1].content
    @episodes = []
  end

  def to_yml
    {
      :episodes => @episodes.collect { |e| e.to_yml },
      :name => @name
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
# File constants
STORE_FILE = "links.pstore"
DUMP_FILE = "series.yml"

begin
  # Make sure that the first option is a URL we can crawl
  # and have a valid serie format
  url = URI(ARGV[0])
  if url.to_s =~ /#{SERIE_PATTERN}/
    root = url.to_s
    pattern = /#{EPISODE_PATTERN}/
  else
    root = URL
    pattern = /#{SERIE_PATTERN}|#{EPISODE_PATTERN}/
  end
rescue
  puts <<-INFO
Usage:
ruby sy_crawler.rb <url>
INFO
  exit(0)
end

# Starts crawling process
Anemone.crawl(root, :storage => Anemone::Storage.PStore(STORE_FILE), :verbose => true) do |anemone|

  # TODO: Use PStore to reduce the amount of memory
  series = []
  episodes = []

  # Focus crawler to follow series or episodes urls
  anemone.focus_crawl do |page|
    page.links.select { |link| link.to_s =~ pattern }
  end

  anemone.on_pages_like(/#{SERIE_PATTERN}/) do |page|
    series << Serie.new(page.doc) unless page.error
  end

  # Parses episodes urls
  anemone.on_pages_like(/#{EPISODE_PATTERN}/) do |page|
    episodes << Episode.new(page.doc) unless page.error
  end

  # Dump information
  anemone.after_crawl do |page|
    File.open(DUMP_FILE, 'w') do |f|
      obj = series.collect do |s|
        # Add related episodes
        episodes.inject(s.episodes) do |acum,e|
          acum << e if s.name.downcase == e.serie.downcase
        end
        # Serialize
        s.to_yml
      end

      YAML.dump(obj, f)
    end
  end

end
