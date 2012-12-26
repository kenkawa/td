require 'spec_helper'
require 'file_reader/shared_context'

require 'stringio'
require 'td/file_reader'

include TreasureData

describe FileReader do
  include_context 'error_proc'

  describe 'initialize' do
    subject { FileReader.new }

    its(:parser_class) { should be_nil }
    its(:opts) { should be_empty }
    [:delimiter_expr, :null_expr, :true_expr, :false_expr].each { |key|
      its(:default_opts) { should have_key(key); }
    }
  end

  let :reader do
    FileReader.new
  end

  describe 'set_format_template' do
    it 'can set csv' do
      reader.set_format_template('csv')
      reader.instance_variable_get(:@format).should == 'text'
      reader.opts.should include(:delimiter_expr => /,/)
    end

    it 'can set tsv' do
      reader.set_format_template('tsv')
      reader.instance_variable_get(:@format).should == 'text'
      reader.opts.should include(:delimiter_expr => /\t/)
    end

    it 'can set msgpack' do
      reader.set_format_template('msgpack')
      reader.instance_variable_get(:@format).should == 'msgpack'
    end

    it 'can set json' do
      reader.set_format_template('json')
      reader.instance_variable_get(:@format).should == 'json'
    end

    it 'raises when set unknown format' do
      expect {
        reader.set_format_template('oreore')
      }.to raise_error(Exception, /Unknown format: oreore/)
    end
  end

  describe 'init_optparse' do
    def parse_opt(argv, &block)
      op = OptionParser.new
      reader.init_optparse(op)
      op.parse!(argv)
      block.call
    end

    context '-f option' do
      ['-f', '--format'].each { |opt|
        ['csv', 'tsv', 'msgpack', 'json'].each { |format|
          it "#{opt} option with #{format}" do
            reader.should_receive(:set_format_template).with(format)
            parse_opt([opt, format]) { }
          end
        }
      }
    end

    context 'columns names option' do
      ['-h', '--columns'].each { |opt|
        it "#{opt} option" do
          columns = 'A,B,C'
          parse_opt([opt, columns]) {
            reader.opts.should include(:column_names => columns.split(','))
          }
        end
      }
    end

    context 'columns header option' do
      ['-H', '--column-header'].each { |opt|
        it "#{opt} option" do
          parse_opt([opt]) {
            reader.opts.should include(:column_header => true)
          }
        end
      }
    end

    context 'delimiter between column option' do
      ['-d', '--delimiter'].each { |opt|
        it "#{opt} option" do
          pattern = '!'
          parse_opt([opt, pattern]) {
            reader.opts.should include(:delimiter_expr => Regexp.new(pattern))
          }
        end
      }
    end

    context 'null expression option' do
      it "--null REGEX option" do
        pattern = 'null'
        parse_opt(['--null', pattern]) {
          reader.opts.should include(:null_expr => Regexp.new(pattern))
        }
      end
    end

    context 'true expression option' do
      it "--true REGEX option" do
        pattern = 'true'
        parse_opt(['--true', pattern]) {
          reader.opts.should include(:true_expr => Regexp.new(pattern))
        }
      end
    end

    context 'false expression option' do
      it "--false REGEX option" do
        pattern = 'false'
        parse_opt(['--false', pattern]) {
          reader.opts.should include(:false_expr => Regexp.new(pattern))
        }
      end
    end

    context 'disable automatic type conversion option' do
      ['-S', '--all-string'].each { |opt|
        it "#{opt} option" do
          parse_opt([opt]) {
            reader.opts.should include(:all_string => true)
          }
        end
      }
    end

    context 'name of the time column option' do
      ['-t', '--time-column'].each { |opt|
        it "#{opt} option" do
          name = 'created_at'
          parse_opt([opt, name]) {
            reader.opts.should include(:time_column => name)
          }
        end
      }
    end

    context 'strftime(3) format of the time column option' do
      ['-T', '--time-format'].each { |opt|
        it "#{opt} option" do
          format = '%Y'
          parse_opt([opt, format]) {
            reader.opts.should include(:time_format => format)
          }
        end
      }
    end

    context 'value of the time column option' do
      require 'time'

      {'int' => lambda { |t| t.to_i.to_s }, 'formatted' => lambda { |t| t.to_s }}.each_pair { |value_type, converter|
        it "--time-value option with #{value_type}" do
          time = Time.now
          parse_opt(['--time-value', converter.call(time)]) {
            reader.opts.should include(:time_value => time.to_i)
          }
        end
      }
    end

    context 'text encoding option' do
      ['-e', '--encoding'].each { |opt|
        it "#{opt} option" do
          enc = 'utf-8'
          parse_opt([opt, enc]) {
            reader.opts.should include(:encoding => enc)
          }
        end
      }
    end

    context 'compression format option' do
      ['-C', '--compress'].each { |opt|
        it "#{opt} option" do
          format = 'gzip'
          parse_opt([opt, format]) {
            reader.opts.should include(:compress => format)
          }
        end
      }
    end
  end

  describe 'compose_factory' do
    it 'returns Proc object' do
      factory = reader.compose_factory
      factory.should be_an_instance_of(Proc)
    end

    # other specs in parse spec
  end

  describe 'parse' do
    let :dataset_header do
      ['name', 'num', 'created_at', 'flag']
    end

    let :dataset_values do
      [
        ['k', 12345, Time.now.to_s, true],
        ['s', 34567, Time.now.to_s, false],
        ['n', 56789, Time.now.to_s, true],
      ]
    end

    let :dataset do
      dataset_values.map { |data|
        Hash[dataset_header.zip(data)]
      }
    end

    def parse_opt(argv, &block)
      op = OptionParser.new
      reader.init_optparse(op)
      op.parse!(argv)
      block.call
    end

    shared_examples_for 'parse --time-value / --time-column cases' do |format, args|
      it "parse #{format} with --time-value" do
        @time = Time.now.to_i
        parse_opt(%W(-f #{format} --time-value #{@time}) + (args || [])) {
          i = 0
          reader.parse(io, error) { |record|
            record.should == dataset[i].merge('time' => @time)
            i += 1
          }
        }
      end

      it 'parse #{format} with --time-column' do
        parse_opt(%W(-f #{format} --time-column created_at) + (args || [])) {
          i = 0
          reader.parse(io, error) { |record|
            record.should == dataset[i].merge('time' => Time.parse(record['created_at']).to_i)
            i += 1
          }
        }
      end
    end

    shared_examples_for 'parse --columns / --column-header cases' do |format|
      converter = "to_#{format}".to_sym

      context 'array format' do
        let :lines do
          dataset_values.map { |data| data.__send__(converter) }
        end

        context 'with --column-columns' do
          it_should_behave_like 'parse --time-value / --time-column cases', format, %W(-h name,num,created_at,flag)
        end

        context 'with --column-header' do
          let :lines do
            [dataset_header.__send__(converter)] + dataset_values.map { |data| data.__send__(converter) }
          end

          it_should_behave_like 'parse --time-value / --time-column cases', format, %W(-H)
        end
      end
    end

    context 'json' do
      require 'json'

      let :lines do
        dataset.map(&:to_json)
      end

      let :io do
        StringIO.new(lines.join("\n"))
      end

      it_should_behave_like 'parse --time-value / --time-column cases', 'json'
      it_should_behave_like 'parse --columns / --column-header cases', 'json'
    end

    context 'msgpack' do
      require 'msgpack'

      let :lines do
        dataset.map(&:to_msgpack)
      end

      let :io do
        StringIO.new(lines.join(""))
      end

      it_should_behave_like 'parse --time-value / --time-column cases', 'msgpack'
      it_should_behave_like 'parse --columns / --column-header cases', 'msgpack'
    end

    [['csv', ','], ['tsv', "\t"]].each { |text_type, pattern|
      context 'text' do
        let :lines do
          dataset_values.map { |data| data.map(&:to_s).join(pattern) }
        end

        let :io do
          StringIO.new(lines.join("\n"))         
        end

        it "raises an exception without --column-header or --columns in #{pattern}" do
          parse_opt(%W(-f #{text_type})) {
            expect {
              reader.parse(io, error)
            }.to raise_error(Exception, /--column-header or --columns option is required/)
          }
        end

        context 'with --column-columns' do
          it_should_behave_like 'parse --time-value / --time-column cases', text_type, %W(-h name,num,created_at,flag)
        end

        context 'with --column-header' do
          let :lines do
            [dataset_header.join(pattern)] + dataset_values.map { |data| data.map(&:to_s).join(pattern) }
          end

          it_should_behave_like 'parse --time-value / --time-column cases', text_type, %W(-H)
        end

        # TODO: Add all_string
      end
    }
  end
end
