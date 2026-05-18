# frozen_string_literal: true

# Net::HTTP などで ASCII-8BIT ラベルになる本文を UTF-8 文字列へ揃える。
module Utf8Bytes
  module_function

  def coerce(value)
    str = value.to_s
    return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

    if str.encoding == Encoding::ASCII_8BIT
      utf8 = str.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?
    end

    str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end
end
