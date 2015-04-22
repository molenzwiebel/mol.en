require 'ruby-graphviz'

module Molen
    def graph(node, output = nil)
        output ||= 'mol.en'

        visitor = GraphVisitor.new
        node.accept visitor

        visitor.graph.output png: "#{output}.png"
    end

    class GraphVisitor < Visitor
        attr_accessor :graph

        def initialize
            @graph = GraphViz.new :G
        end

        def visit_any(ast)
            node = graph.add_nodes(String.random(11), {:label => ast.class.name})
            ast.instance_variables.each do |var|
                next if var == :@parent
                val = ast.instance_variable_get var
                next unless val
                if var == :@target then
                    graph.add_edges(node, graph.add_nodes(String.random(11), {:label => val.ir_name}), {:label => "@target"})
                    next
                end

                n = node_obj(val)
                (graph.add_edges node, n, {:label => var.to_s}) if n
            end
            node
        end

        def node_obj(val)
            if val.is_a? ASTNode then
                return val.accept self
            end
            return graph.add_nodes(String.random(11), {:label => val.name}) if val.is_a? Type
            return graph.add_nodes(String.random(11), {:label => val.to_s}) unless val.is_a? Array or val.is_a? Hash

            if val.is_a? Array
                node = graph.add_nodes(String.random(11), {:label => "Array"})
                val.each_with_index do |val, i|
                    graph.add_edges node, node_obj(val), {:label => i.to_s}
                end
                return node
            else
                node = graph.add_nodes(String.random(11), {:label => "Hash"})
                val.each do |key, val|
                    graph.add_edges node, node_obj(val), {:label => key.to_s}
                end
                return node
            end
        end
    end
end