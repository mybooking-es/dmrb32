# DMRB32

## 1. Crear un fichero de entorno .env con la URL de conexión

mysql://USER:PASSWORD@HOST:PUERTO/DB

## 2. Ejecución en Ruby 3.1.4

 ~ (0.000328) SELECT COUNT(*) FROM `demos`
"elementos: 2"

## 3. Ejecución en Ruby 3.2.2

Cuando se ejecuta el proyecto en Ruby 3.2.2 da este error

Esta es la línea del error

        element_count = Demo.count

Este es el error

        ~ undefined method `field' for #<DataMapper::Query::Operator @target=:all @operator=:count>
        /Users/jgil/proyectos/dmrb32/vendor/dm-do-adapter/lib/dm-do-adapter/adapter.rb:324:in `property_to_column_name': undefined method `field' for #<DataMapper::Query::Operator @target=:all @operator=:count> (NoMethodError)

                  column_name << quote_name(property.field)
                                                    ^^^^^^

# 4. Cuál es el problema

Está con el módulo vendor/dm-core/lib/support/chainable.rb

En vendor/dm-aggregates/adapters/dm-do-adapter.rb línea 64 :

- En Ruby 3.1.4 parece que aplica chainable y de hecho puedes ver los puts DM-AGGREGATE-property y sin embargo en la 3.2.2 no lo aplica.

El objetivo es poder definir chainable con la sintaxis para que funcione en la 3.2.2 ya que se utiliza en todo el ORM
