
module Molen
    class Visitor
        ['expressions', 'bool', 'int', 'double', 'string'].each do |name|
            class_eval %Q(
                def start_visit_#{name}(node)
                  true
                end
                def end_visit_#{name}(node)
                end
                def visit_#{name}(node)
                    start_visit_#{name} node
                    end_visit_#{name} node
                end
            )
        end
    end
end