#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'fileutils'
require 'open3'

class RDFConfig
  require 'rdf-config/config'
  require 'rdf-config/model'
  require 'rdf-config/sparql'
  require 'rdf-config/stanza'
  require 'rdf-config/schema/senbero'
  require 'rdf-config/schema/chart'

  def initialize(opts = {})
    @config = Config.new(opts[:config_dir])
    @opts = opts
  end

  def exec(opts)
    case opts[:mode]
    when :sparql
      puts generate_sparql
    when :query
      run_sparql
    when :stanza_rb
      generate_stanza_rb
    when :stanza_js
      generate_stanza_js
    when :senbero
      generate_senbero
    when :chart
      generate_chart
    end
  end

  def generate_sparql
    sparql = SPARQL.new(@config, @opts)
    sparql.generate
  end

  def run_sparql
    sparql = SPARQL.new(@model, @opts)
    sparql.run
  end

  def generate_stanza_rb
    stanza = Stanza::Ruby.new(@model, @opts)
    stanza.generate
  end

  def generate_stanza_js
    stanza = Stanza::JavaScript.new(@model, @opts)
    stanza.generate
  end

  def generate_senbero
    senbero = Schema::Senbero.new(@config)
    senbero.generate
  end

  def generate_chart
    schema = Schema::Chart.new(@config)
    schema.generate
  end
end
