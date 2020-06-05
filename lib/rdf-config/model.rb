class RDFConfig

  class Model
    attr_reader :yaml, :prefix

    def initialize(config_dir)
      @config_dir = config_dir

      parse_prefix("#{@config_dir}/prefix.yaml")
      parse_model("#{@config_dir}/model.yaml")
    end

    def parse_prefix(prefix_config_file)
      @prefix = YAML.load_file(prefix_config_file)
    end

    def parse_model(model_config_file)
      @yaml = YAML.load_file(model_config_file)
    end

    def subjects
      subject_instances = []
      @yaml.each do |subject_hash|
        subject_instances << RDFConfig::Model::Subject.new(subject_hash, @prefix)
      end

      subject_instances
    end

    def triples
      triple_instances = []
      @yaml.each do |subject_hash|
        triple_instances += RDFConfig::Model::Triple.instances(subject_hash, @prefix)
      end

      triple_instances
    end

    def parse_sparql
      YAML.load_file("#{@config_dir}/sparql.yaml")
    end

    def parse_endpoint
      YAML.load_file("#{@config_dir}/endpoint.yaml")
    end

    def parse_stanza
      YAML.load_file("#{@config_dir}/stanza.yaml")
    end
  end
end
