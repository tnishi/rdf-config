require 'yaml'

class RDFConfig
  class Config
    def initialize(config_dir)
      @config_dir = config_dir
    end

    def model
      @model ||= YAML.load_file("#{@config_dir}/model.yaml")
    end

    def prefix
      @prefix ||= YAML.load_file("#{@config_dir}/prefix.yaml")
    end

    def sparql
      @sparql ||= YAML.load_file("#{@config_dir}/sparql.yaml")
    end

    def endpoint
      @endpoint ||= YAML.load_file("#{@config_dir}/endpoint.yaml")
    end

    def stanza
      @stanza ||= YAML.load_file("#{@config_dir}/stanza.yaml")
    end

    def metadata
      @metadata ||= YAML.load_file("#{@config_dir}/metadata.yaml")
    end

    def metadata?
      File.exist?("#{@config_dir}/metadata.yaml")
    end

  end
end
