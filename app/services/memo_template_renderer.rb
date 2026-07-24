# frozen_string_literal: true

class MemoTemplateRenderer
  CREATED_ON_MACRO = "{{created_on}}"
  Result = Data.define(:title, :body, :tag_list)

  def initialize(template:, created_on: Date.current)
    @template = template
    @created_on = created_on.to_date
  end

  def call
    Result.new(
      title: expand(@template.title_template),
      body: expand(@template.body_template),
      tag_list: expand(@template.tag_list)
    )
  end

  private

  def expand(value)
    value.to_s.gsub(CREATED_ON_MACRO, @created_on.iso8601)
  end
end
