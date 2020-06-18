require 'rdf-config/model'
require 'rdf-config/sparql/sparql_builder'
require 'rdf-config/sparql/comment_builder'
require 'rdf-config/sparql/prefix_builder'
require 'rdf-config/sparql/select_builder'
require 'rdf-config/sparql/where_builder'

class RDFConfig
  class SPARQL
    DEFAULT_NAME = 'sparql'.freeze

    attr_accessor :offset, :limit

    def initialize(config, opts = {})
      @config = config
      @opts = opts

      raise SPARQLConfigNotFound, "No SPARQL config found: sparql query name '#{name}'" unless @config.sparql.key?(name)
    end

    def generate
      sparql_builder = SPARQLBuilder.new

      sparql_builder.add_builder(CommentBuilder.new(@config, @opts))
      sparql_builder.add_builder(PrefixBuilder.new(@config, @opts))
      sparql_builder.add_builder(SelectBuilder.new(@config, @opts))
      sparql_builder.add_builder(WhereBuilder.new(@config, @opts))

      sparql_builder.build.join("\n")
    end

    def name
      @name = if @opts[:sparql_query_name].to_s.empty?
                DEFAULT_NAME
              else
                @opts[:sparql_query_name]
              end
    end

    def variables
      @variables ||=
        @config.sparql[name].key?('variables') ? @config.sparql[name]['variables'] : []
    end

    def parameters
      @parameters ||=
        @config.sparql[name].key?('parameters') ? @config.sparql[name]['parameters'] : {}
    end

    def description
      @description ||=
        @config.sparql[name].key?('description') ? @config.sparql[name]['description'] : ''
    end

    def endpoints
      case @config.endpoint['endpoint']
      when String
        [@config.endpoint['endpoint']]
      when Array
        @config.endpoint['endpoint']
      else
        []
      end
    end

    def endpoint
      endpoints.first
    end

    def namespace
      @namespace ||= @config.prefix
    end

    def model
      @model ||= Model.new(@config)
    end

    def run
      endpoint_uri = URI.parse(@endpoint)

      sparql_query = generate
      puts sparql_query

      http = Net::HTTP.new(endpoint_uri.host, endpoint_uri.port)
      http.use_ssl = endpoint_uri.scheme == 'https'
      headers = {
          'Accept' => 'application/sparql-results+json',
          'Content-Type' => 'application/x-www-form-urlencoded'
      }

      url_path = endpoint_uri.path
      url_query = URI.encode_www_form({query: sparql_query})
      response = http.get("#{url_path}?#{url_query}", headers)
      case response.code
      when '200'
        pp JSON.parse(response.body)
      else
        puts response.body
      end
    end

    class SPARQLConfigNotFound < StandardError; end
  end
end
