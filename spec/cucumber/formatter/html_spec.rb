require File.dirname(__FILE__) + '/../../spec_helper'
require 'cucumber/formatter/html'
require 'nokogiri'
require 'cucumber/rb_support/rb_language'

module Cucumber
  module Formatter
    module SpecHelperDsl
      attr_reader :feature_content, :step_defs
      
      def define_feature(string)
        @feature_content = string
      end
      
      def define_steps(&block)
        @step_defs = block
      end
    end
    module SpecHelper
      def load_features(content)
        feature_file = FeatureFile.new(nil, content)
        features = Ast::Features.new
        features.add_feature feature_file.parse(@step_mother, {})
        features
      end
      
      def run(features)
        # options = { :verbose => true }
        options = {}
        tree_walker = Cucumber::Ast::TreeWalker.new(@step_mother, [@formatter], options, STDOUT)
        tree_walker.visit_features(features)
      end
      
      def define_steps
        return unless step_defs = self.class.step_defs
        rb = @step_mother.load_programming_language('rb')
        dsl = Object.new 
        dsl.extend RbSupport::RbDsl
        dsl.instance_exec &step_defs
        @step_mother.register_step_definitions(rb.step_definitions)
      end
      
      Spec::Matchers.define :have_css_node do |css, regexp|
        match do |doc|
          nodes = doc.css(css)
          nodes.detect{ |node| node.text =~ regexp }
        end
      end
    end
    
    describe Html do
      before(:each) do
        @out = StringIO.new
        @formatter = Html.new(mock("step mother"), @out, {})
        @step_mother = StepMother.new
      end
      
      extend SpecHelperDsl
      include SpecHelper

      it "should not raise an error when visiting a blank feature name" do
        lambda { @formatter.feature_name("") }.should_not raise_error
      end
      
      describe "given a single feature" do
        before(:each) do
          features = load_features(self.class.feature_content || raise("No feature content defined!"))
          define_steps
          run(features)
          @doc = Nokogiri.HTML(@out.string)
        end
        
        describe "with a comment" do
          define_feature <<-FEATURE
            # Healthy
          FEATURE
          
          it { @out.string.should =~ /^\<!DOCTYPE/ }
          it { @out.string.should =~ /\<\/html\>$/ }
          it { @doc.should have_css_node('.feature .comment', /Healthy/) }
        end
        
        describe "with a tag" do
          define_feature <<-FEATURE
            @foo
          FEATURE

          it { @doc.should have_css_node('.feature .tag', /foo/) }
        end
        
        describe "with a narrative" do
          define_feature <<-FEATURE
            Feature: Bananas
              In order to find my inner monkey
              As a human
              I must eat bananas
          FEATURE

          it { @doc.should have_css_node('.feature h2', /Bananas/) }
          it { @doc.should have_css_node('.feature .narrative', /must eat bananas/) }
        end
        
        describe "with a background" do
          define_feature <<-FEATURE
            Feature: Bananas
            
            Background:
              Given there are bananas
          FEATURE

          it { @doc.should have_css_node('.feature .background', /there are bananas/) }
        end
        
        describe "with a scenario" do
          define_feature <<-FEATURE
            Scenario: Monkey eats banana
              Given there are bananas
          FEATURE

          it { @doc.should have_css_node('.feature h3', /Monkey eats banana/) }
          it { @doc.should have_css_node('.feature .scenario .step', /there are bananas/) }
        end
        
        describe "with a scenario outline" do
          define_feature <<-FEATURE
            Scenario Outline: Monkey eats a balanced diet
              Given there are <Things>
            
              Examples: Fruit
               | Things  |
               | apples  |
               | bananas |
              Examples: Vegetables
               | Things   |
               | broccoli |
               | carrots  |
          FEATURE
          
          it { @doc.should have_css_node('.feature .scenario.outline h4', /Fruit/) }
          it { @doc.should have_css_node('.feature .scenario.outline h4', /Vegetables/) }
          it { @doc.css('.feature .scenario.outline h4').length.should == 2}
          it { @doc.should have_css_node('.feature .scenario.outline table', //) }
          it { @doc.should have_css_node('.feature .scenario.outline table td', /carrots/) }
        end
        
        describe "with a step with a py string" do
          define_feature <<-FEATURE
            Scenario: Monkey goes to town
              Given there is a monkey called:
               """
               foo
               """
          FEATURE
          
          it { @doc.should have_css_node('.feature .scenario .val', /foo/) }
        end

        describe "with a multiline step arg" do
          define_feature <<-FEATURE
            Scenario: Monkey goes to town
              Given there are monkeys:
               | name |
               | foo  |
               | bar  |
          FEATURE
          
          it { @doc.should have_css_node('.feature .scenario table td', /foo/) }
        end
        
        describe "with a table in the background and the scenario" do
          define_feature <<-FEATURE
            Background:
              Given table:
                | a | b |
                | c | d |
            Scenario:
              Given another table:
               | e | f |
               | g | h |
          FEATURE
          
          it { @doc.css('td').length.should == 8 }
        end
        
        describe "with a py string in the background and the scenario" do
          define_feature <<-FEATURE
            Background:
              Given stuff:
                """
                foo
                """
            Scenario:
              Given more stuff:
                """
                bar
                """
          FEATURE

          it { @doc.css('.feature .background pre.val').length.should == 1 }
          it { @doc.css('.feature .scenario pre.val').length.should == 1 }
        end
        
        describe "with a step that fails in the scenario" do
          define_steps do
            Given(/boo/) { raise 'eek' }
          end
          
          define_feature(<<-FEATURE)
            Scenario: Monkey gets a fright
              Given boo
            FEATURE
        
          it { @doc.should have_css_node('.feature .scenario .step.failed', /eek/) }
        end
        
        describe "with a step that fails in the backgound" do
          define_steps do
            Given(/boo/) { raise 'eek' }
          end
          
          define_feature(<<-FEATURE)
            Background:
              Given boo
            Scenario:
              Given yay
            FEATURE
          
          it { @doc.should have_css_node('.feature .background .step.failed', /eek/) }
          it { @doc.should_not have_css_node('.feature .scenario .step.failed', //) }
          it { @doc.should have_css_node('.feature .scenario .step.undefined', /yay/) }
        end
        
      end
    end
  end
end

