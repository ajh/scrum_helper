require "application_configuration"
require 'active_support/all'
require 'httparty'
require 'pp'
require 'uri'

class ScrumHelper < Thor
  USER_CONFIG_PATH = Pathname.new("~/.scrum_helper.yml").expand_path.freeze
  CONFIG = ApplicationConfiguration.new \
    Pathname.new(__FILE__).join("..", "..", "defaults.yml"),
    USER_CONFIG_PATH,
    Pathname.new(Dir.getwd).join("scrum_helper.yml")

  desc "search QUERY", "search trello cards for QUERY"
  def search(query)
    params = {
      query: query,
      key: CONFIG.oauth.key,
      token: CONFIG.oauth.token,
      modelTypes: "cards",
      card_fields: "name,url,closed",
      cards_limit: 1000,
      card_board: true,
      board_fields: "name",
      card_list: "true",
    }
    uri = URI('https://api.trello.com/1/search')
    uri.query = params.to_query

    response = HTTParty.get uri.to_s

    if response.code == 200
      # create data structure like [
      # {name: "board 1", lists: [
      #   {name: "list a", cards: [cards]}]
      # }]
      boards = []
      ActiveSupport::JSON.decode(response.body)["cards"].each do |c|
        c["closed"] == false or next

        board = boards.find {|b| b[:name] == c["board"]["name"]}
        unless board
          board = {name: c["board"]["name"], lists: [], points: 0}
          boards << board
        end

        list = board[:lists].find {|l| l[:name] == c["list"]["name"]}
        unless list
          list = {name: c["list"]["name"], cards: [], points: 0}
          board[:lists] << list
        end

        points = c["name"].match(/\((\d+)\)/).try(:[], 1).try :to_i

        card = {
          name: c["name"],
          url: c["url"],
          points:  points,
        }

        list[:cards] << card
        list[:points] += points if points
        board[:points] += points if points
      end

      sorter = lambda {|thing_with_name| thing_with_name[:name]}

      boards.sort_by(&sorter).each do |board|
        board[:lists].sort_by(&sorter).each do |list|
          puts "# #{board[:name]} - #{list[:name]} (#{list[:points]})"

          list[:cards].sort_by(&sorter).each do |card|
            puts "* #{card[:name]} - #{card[:url]}"
          end

          puts
        end
      end

      total_points = boards.inject(0) do |sum, b|
        b[:points] ? sum + b[:points] : sum
      end

      puts "# Total Points\n#{total_points}"

    else
      warn({
        body: response.body,
        code: response.code,
        message: response.message,
        headers: response.headers.pretty_inspect
      }.pretty_inspect)
      exit 1
    end
  end
end
