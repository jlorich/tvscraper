require 'yaml'
require 'net/http'
require 'uri'
require 'rss'
require 'pry'
require 'fileutils'

class TVShowManager
  attr_accessor :show_storage_root_path, :shows
  
  def initialize(show_storage_root_path)
    self.show_storage_root_path = show_storage_root_path
    self.shows = {}
  end

  def directory_exists?(directory)
    File.directory?(directory)
  end

  def create_media_directory(path)
    Dir.mkdir(path, 0755)
    FileUtils.chown 'media', 'media', path
  end

  # Returns the path to a specific show
  def path_for_show(show_name)
    File.join self.show_storage_root_path, show_name
  end

  def path_for_season(show_name, season)
   File.join path_for_show(show_name), "Season #{season}"
  end

  def parse_season(show_name, season)
    puts "Parsing #{show_name} Season #{season}"

    season_path = path_for_season show_name, season
    self.shows[show_name][season] = {}

    Dir.foreach(season_path) do |item|
      next if item == '.' or item == '..'
      
      match = /#{show_name} - Season (?<season>\d+) - Episode (?<episode>\d+) - (?<title>.*)\.[a-zA-Z]{2,}/.match item

      if (match)
        self.shows[show_name][season][match[:episode]] = {
          full_path: File.join(season_path, item),
          title: match[:title]
        }
      end
    end

    def has_episode?(show_name, season, episode)
      return false if self.shows[show_name].nil?
      return false if self.shows[show_name][season.to_s].nil?

      !self.shows[show_name][season.to_s][episode.to_s].nil?
    end
  end

  def parse_show(show_name)
    puts "Parsing #{show_name}"

    show_path = path_for_show show_name

    create_media_directory show_path if (!directory_exists? show_path)

    self.shows[show_name] = {}

    Dir.foreach(show_path) do |item|
      next if item == '.' or item == '..'
      
      match = /Season (?<season>\d+)/.match item

      if (match)
        parse_season show_name, match[:season]
      end
    end
  end

  def parse_file_name(file_name)
    expession_list = [
      /^(?<show_name>[a-zA-Z0-9\s]+[ -]*) (?<season>[\d]+)x(?<episode>[\d]+).*$/,
      /^(?<show_name>[a-zA-Z0-9\s]+) - (?<description>[a-zA-Z0-9\s]+) (?<season>[\d]+)x(?<episode>[\d]+).*/ 
    ]

    expession_list.each do |expression|
      match = expression.match file_name

      if match
        return nil if !match.names.include?('show_name') ||
                      !match.names.include?('season')
                      !match.names.include?('episode')

        return {}.tap { |show|
          show[:show_name] = match[:show_name]
          show[:description] = match[:description] if match.names.include?('description')
          show[:season] = match[:season]
          show[:episode] = match[:episode]
        }
      end
    end

    nil
  end

end

class ShowScraper
  attr_accessor :config, :shows, :show_manager, :show_storage_root_path, :download_path, :watch_path

  # Loads the config and starts the scraping
  def initialize (config_path)
    load_config config_path

    self.show_manager = TVShowManager.new(self.show_storage_root_path)
    self.shows.each do |show_name|
      puts "Processing #{show_name}"

      self.show_manager.parse_show show_name
      scrape(show_name)
    end
  end

  # Loads the config
  def load_config(path)
    file = File.open(path, 'r')
    data = file.read

    self.config = YAML.load(data)
    self.shows = config['TV Shows']
    self.show_storage_root_path = config['TV Show Storage Root Path']
    self.download_path = config['Download Path']
    self.watch_path = config['Torrent Watch Path']
  end

  def load(url)
    Net::HTTP.get(URI.parse(url))
  end

  def scrape(show)
    base_url = self.config["Search URL"]

    begin
      rss = load(URI.escape(base_url.sub "%s", show))
      feed = RSS::Parser.parse(rss)

      feed.items.each do |feed_show|
        begin
          title = feed_show.title
          link = feed_show.link
          episode = self.show_manager.parse_file_name(title)

          if episode == nil
            puts " Failure to parse title: #{title}"
            next
          end

          if (self.show_manager.has_episode? episode[:show_name], episode[:season], episode[:episode])
            #puts "Has #{episode[:show_name]} - Season #{episode[:season]} - Episode #{episode[:episode]}"
          else
            puts "Needs #{episode[:show_name]} - Season #{episode[:season]} - Episode #{episode[:episode]}"
          end
        rescue Exception => e
          puts e
          # do nothing, it's fine, xml sucks
        end
      end
    rescue Exception => e
      puts '  - ERROR PARSING FEED'
      return false
      # do nothing, it's fine, xml sucks
    end
  end
end

ShowScraper.new('./tv shows.yml')