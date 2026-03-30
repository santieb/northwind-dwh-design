{% test column_type(model, column_name, type) %}

{#
  Generic test that asserts the actual BigQuery data type of a column
  matches the expected type by querying INFORMATION_SCHEMA.COLUMNS.

  Returns rows when the column type does not match the expected type,
  causing dbt to mark the test as failed.

  Usage in schema.yml:
    columns:
      - name: my_column
        tests:
          - column_type:
              type: INT64
#}

select column_name
from {{ model.database }}.{{ model.schema }}.INFORMATION_SCHEMA.COLUMNS
where table_name = '{{ model.identifier }}'
  and column_name = '{{ column_name }}'
  and data_type != '{{ type }}'

{% endtest %}
