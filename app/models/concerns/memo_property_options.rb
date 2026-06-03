# frozen_string_literal: true

# メモの試行錯誤向けオプション項目。正は memos.properties（jsonb）。
# 方針: docs/architecture/memo-properties.adoc
module MemoPropertyOptions
  extend ActiveSupport::Concern

  SCHEDULED_ON_KEY = "scheduled_on"
  MEDIA_ALBUM_ID_KEY = "media_album_id"

  def scheduled_on
    parse_property_date(properties[SCHEDULED_ON_KEY])
  end

  def scheduled_on=(value)
    write_property_date(SCHEDULED_ON_KEY, value)
  end

  def media_album_id
    raw = properties[MEDIA_ALBUM_ID_KEY]
    return nil if raw.blank?

    raw.to_s.upcase
  end

  def media_album_id=(value)
    write_property_string(MEDIA_ALBUM_ID_KEY, value.presence&.to_s&.upcase)
  end

  private

  def write_property_string(key, value)
    props = properties.stringify_keys.dup
    if value.blank?
      props.delete(key)
    else
      props[key] = value
    end
    self.properties = props
  end

  def parse_property_date(raw)
    return nil if raw.blank?

    Date.iso8601(raw.to_s)
  rescue ArgumentError
    nil
  end

  def write_property_date(key, value)
    props = properties.stringify_keys.dup
    if value.blank?
      props.delete(key)
    else
      props[key] = value.to_date.iso8601
    end
    self.properties = props
  end
end
