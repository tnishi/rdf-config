class RDFConfig
  class SPARQL
    require 'rdf-config/model/triple'

    attr_reader :parameters, :variables

    def initialize(model, opts)
      @query_name = if opts[:sparql_query_name].to_s.empty?
                      'sparql'
                    else
                      opts[:sparql_query_name]
                    end

      @prefixes = model.prefix
      @sparql_config = model.parse_sparql
      @triples = model.triples

      if @sparql_config.key?(@query_name)
        @parameters = current_sparql.key?('parameters') ? current_sparql['parameters'] : {}
        @variables = current_sparql['variables']
      else
        raise "Error: No SPARQL query (#{@query_name}) exists."
      end

      @endpoint_config = model.parse_endpoint
    end

    def current_sparql
      @sparql_config[@query_name]
    end

    def generate
      sparql_lines = comment_lines

      sparql_lines += prefix_lines_for_sparql
      sparql_lines << ''
      sparql_lines << select_line
      sparql_lines << 'WHERE {'
      sparql_lines += values_lines
      sparql_lines += where_phase_lines(@variables)
      sparql_lines << '}'
      sparql_lines << 'LIMIT 100'

      sparql_lines.join("\n")
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

    def comment_lines
      lines = []

      endpoints = all_endpoints.dup
      lines << "# Endpoint: #{endpoints.shift}"
      endpoints.each do |endpoint|
        lines << "#           #{endpoint}"
      end

      lines << "# Description: #{description}"

      first_parameter = true
      @parameters.each do |var_name, value|
        if first_parameter
          first_parameter = false
          s = '# Parameter: '
        else
          s = '#            '
        end
        lines << "#{s}#{var_name}: (example: #{value})"
      end
      lines << ''

      lines
    end

    def prefix_lines_for_sparql(variables = @variables, parameters = @parameters)
      prefixes = used_prefixes(variables, parameters)

      prefix_lines = []
      @prefixes.each do |prefix, uri|
        prefix_lines << "PREFIX #{prefix}: #{uri}" if prefixes.include?(prefix)
      end

      prefix_lines
    end

    def select_line
      %/SELECT #{select_var_names.map { |name| "?#{name}" }.join(' ')}/
    end

    def values_lines(parameters = @parameters)
      lines = []

      parameters.each do |var_name, value|
        object = @triples.map(&:object).select { |object| object.name == var_name }.first
        if object.is_a?(RDFConfig::Model::Literal)
          value = %Q("#{value}")
        end
        lines << "  VALUES ?#{var_name} { #{value} }"
      end

      lines
    end

    def where_phase_lines(var_names)
      triple = sparql_triple_lines(var_names)
      lines = []
      triple[:required].each do |subject_name, properties|
        next if properties.empty?

        if properties.size > 1
          first_line = properties.shift
          last_line = properties.pop
          lines << "  ?#{subject_name} #{first_line[0]} #{first_line[1]} ;"
          properties.each do |property|
            lines << "      #{property[0]} #{property[1]} ;"
          end
          lines << "      #{last_line[0]} #{last_line[1]} ."
        else
          lines << "  ?#{subject_name} #{properties[0][0]} #{properties[0][1]} ."
        end
      end

      triple[:optional].each do |subject_name, properties|
        properties.each do |property|
          lines << "  OPTIONAL { ?#{subject_name} #{property[0]} #{property[1]} . }"
        end
      end

      lines
    end

    def sparql_triple_lines(variable_names)
      required_lines = {}
      optional_lines = {}
      variable_names.each do |variable_name|
        next if @triples.map(&:subject).map(&:name).include?(variable_name)

        triple = @triples.select { |triple| triple.object.name == variable_name }.first
        subject = triple.subject
        required_lines[subject.name] = [['a', subject.type]] unless required_lines.key?(subject.name)
        optional_lines[subject.name] = [] unless optional_lines.key?(subject.name)

        property_phrase = [triple.property_path, "?#{variable_name}"]

        predicate = triple.predicates.last
        if predicate.sparql_optional_phrase?
          optional_lines[subject.name] << property_phrase
        else
          required_lines[subject.name] << property_phrase
        end
      end

      { required: required_lines, optional: optional_lines }
    end

    def select_var_names
      @variables
    end

    def used_prefixes_by_variable(variable_names)
      prefixes = []

      variable_names.each do |variable_name|
        next if @triples.map(&:subject).map(&:name).include?(variable_name)

        triple = @triples.select { |triple| triple.object.name == variable_name }.first
        next if triple.nil?

        triple.predicates.each do |predicate|
          if /\A(\w+):\w+\z/ =~ predicate.uri
            prefix = Regexp.last_match(1)
            prefixes << prefix unless prefixes.include?(prefix)
          end
        end
      end

      prefixes
    end

    def used_prefixes(variables = @variables, parameters = @parameters)
      prefixes = used_prefixes_by_variable(variables)
      parameters.each do |var_name, value|
        object = @triples.map(&:object).select { |object| object.name == var_name }.first
        next unless object.is_a?(RDFConfig::Model::URI)

        if /\A(\w+):(.+)/ =~ value && !prefixes.include?($1)
          prefixes << $1
        end
      end

      prefixes
    end

    def has_parameters?
      !@parameters.empty?
    end

    def description
      current_sparql['description'].to_s
    end

    def all_endpoints
      case @endpoint_config['endpoint']
      when String
        [@endpoint_config['endpoint']]
      when Array
        @endpoint_config['endpoint']
      end
    end

    def endpoint
      case @endpoint_config['endpoint']
      when String
        @endpoint_config['endpoint']
      when Array
        @endpoint_config['endpoint'].first
      end
    end

  end

end
