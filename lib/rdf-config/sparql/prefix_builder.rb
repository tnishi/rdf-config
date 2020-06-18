class RDFConfig
  class SPARQL
    class PrefixBuilder < SPARQL
      def initialize(config, opts = {})
        super
      end

      def build
        lines = []

        used_prefixes.uniq.each do |prefix|
          lines << "PREFIX #{prefix}: #{namespace[prefix]}"
        end
        lines << ''

        lines
      end

      private

      def used_prefixes
        prefixes = used_prefixes_by_variable
        parameters.each do |var_name, value|
          object = model.find_object(var_name)
          next unless object.is_a?(RDFConfig::Model::URI)

          if /\A(\w+):(.+)/ =~ value && !prefixes.include?($1)
            prefixes << $1
          end
        end

        prefixes
      end

      def used_prefixes_by_variable
        prefixes = []

        variables.each do |variable_name|
          next if model.subject?(variable_name)

          triple = model.find_by_object_name(variable_name)
          next if triple.nil?

          uris = triple.subject.types + triple.predicates.map(&:uri)
          uris.each do |uri|
            if /\A(\w+):\w+\z/ =~ uri
              prefix = Regexp.last_match(1)
              prefixes << prefix unless prefixes.include?(prefix)
            end
          end
        end

        prefixes
      end

    end
  end
end
