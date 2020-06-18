require 'fileutils'
require 'rdf-config/sparql/sparql_builder'
require 'rdf-config/stanza/javascript'
require 'rdf-config/stanza/ruby'

class RDFConfig
  class Stanza
    DEFAULT_NAME = 'stanza'.freeze

    def initialize(config, opts = {})
      @config = config
      @opts = opts

      raise StanzaConfigNotFound, "No stanza config found: stanza name '#{name}'" unless @config.stanza.key?(name)
    end

    def generate
      mkdir(stanza_base_dir) unless File.exist?(stanza_base_dir)
      STDERR.puts "Generate stanza: #{name}"

      generate_template
      update_metadata_json
      update_stanza_html
      generate_sparql
    end

    def output_metadata_json(metadata)
      output_to_file(metadata_json_fpath, JSON.pretty_generate(metadata))
    end

    def update_metadata_json
      output_metadata_json(metadata_hash)
    end

    def update_stanza_html
      output_to_file(stanza_html_fpath, stanza_html)
    end

    def generate_sparql
      output_to_file(sparql_fpath, sparql_query)
    end

    def metadata_hash(prefix = '')
      metadata = {}

      metadata["#{prefix}parameter"] = parameters_for_metadata(prefix)
      metadata["#{prefix}label"] = label
      metadata["#{prefix}definition"] = definition

      if @config.metadata?
        metadata["#{prefix}provider"] = provider
        metadata["#{prefix}license"] = licenses.join("\n")
        metadata["#{prefix}author"] = creators.join(', ')
      end

      metadata
    end

    def parameters_for_metadata(prefix = '')
      params = []

      parameters.each do |key, parameter|
        params << {
            "#{prefix}key" => key,
            "#{prefix}example" => parameter['example'],
            "#{prefix}description" => parameter['description'],
            "#{prefix}required" => parameter['required'],
        }
      end

      params
    end

    def sparql_query
      sparql_builder = SPARQL::SPARQLBuilder.new

      sparql_builder.add_builder(sparql_prefix_builder)
      sparql_builder.add_builder(sparql_select_builder)
      sparql_builder.add_builder(sparql_where_builder)

      sparql_builder.build.join("\n")
    end

    def sparql_result_html(suffix = '', indent_chars = '  ')
      lines = []

      lines << "{{#each #{name}}}"
      lines << %(#{indent_chars}<dl class="dl-horizontal">)
      sparql.variables.each do |var_name|
        lines << "#{indent_chars * 2}<dt>#{var_name}</dt><dd>{{#{var_name}#{suffix}}}</dd>"
      end
      lines << "#{indent_chars}</dl>"
      lines << '{{/each}}'

      lines.join("\n")
    end

    def sparql
      @sparql ||= SPARQL.new(@config, sparql_query_name: stanza_conf['sparql'])
    end

    def name
      @name = if @opts[:stanza_name].to_s.empty?
                DEFAULT_NAME
              else
                @opts[:stanza_name]
              end
    end

    def output_dir
      stanza_conf['output_dir']
    end

    def label
      stanza_conf['label']
    end

    def definition
      stanza_conf['definition']
    end

    def parameters
      stanza_conf['parameters']
    end

    def provider
      metadata_conf['provider'].to_s
    end

    def creators
      if metadata_conf.key?('creators')
        case metadata_conf['creators']
        when Array
          case metadata_conf['creators'].first
          when Hash
            metadata_conf['creators'].map { |creator| creator['name'] }
          else
            metadata_conf['creators']
          end
        else
          [metadata_conf['creators']]
        end
      else
        []
      end
    end

    def licenses
      if metadata_conf.key?('licenses')
        case metadata_conf['licenses']
        when Array
          metadata_conf['licenses']
        else
          [metadata_conf['licenses']]
        end
      else
        []
      end
    end

    private

    def stanza_conf
      @stanza ||= @config.stanza[name]
    end

    def metadata_conf
      @metadata ||= @config.metadata
    end

    def sparql_prefix_builder
      @sparql_prefix_builder = SPARQL::PrefixBuilder.new(
          @config, sparql_query_name: stanza_conf['sparql']
      )
    end

    def sparql_select_builder
      @sparql_select_builder = SPARQL::SelectBuilder.new(
          @config, sparql_query_name: stanza_conf['sparql']
      )
    end

    def sparql_where_builder
      @sparql_select_builder = SPARQL::WhereBuilder.new(
          @config,
          sparql_query_name: stanza_conf['sparql'], template: true
      )
    end

    def mkdir(dir)
      FileUtils.mkdir_p(dir)
    end

    def output_to_file(fpath, data)
      File.open(fpath, 'w') do |f|
        f.puts data
      end
    end

    def stanza_base_dir
      "#{output_dir}/#{@stanza_type}"
    end

    def stanza_dir
      "#{stanza_base_dir}/#{name}"
    end

    def metadata_json_fpath
      "#{stanza_dir}/metadata.json"
    end

    class StanzaConfigNotFound < StandardError; end
    class StanzaExecutionFailure < StandardError; end
  end
end
