# frozen_string_literal: true

require "test_helper"

module AgentChat
  class TsuzuraUploadTest < ActiveSupport::TestCase
    test "extracts media id from media_item_id field" do
      file = uploaded_file("photo.jpg", "image/jpeg", "JPEG")
      response = Object.new
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      response.define_singleton_method(:body) do
        JSON.generate(items: [ { media_item_id: "01JABCDEFGHJKMNPQRSTVWXYZ0" } ])
      end

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }

      Net::HTTP.stub(:start, http) do
        result = TsuzuraUpload.call(file: file, cookie_header: "session=test")
        assert_equal "01JABCDEFGHJKMNPQRSTVWXYZ0", result.tsuzura_media_id
      end
    end

    test "extracts media id from batch response" do
      file = uploaded_file("photo.jpg", "image/jpeg", "JPEG")
      response = Object.new
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      response.define_singleton_method(:body) do
        JSON.generate(items: [ { id: "01JABCDEFGHJKMNPQRSTVWXYZ0" } ])
      end

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }

      Net::HTTP.stub(:start, http) do
        result = TsuzuraUpload.call(file: file, cookie_header: "session=test")
        assert_equal "01JABCDEFGHJKMNPQRSTVWXYZ0", result.tsuzura_media_id
        assert_equal "photo.jpg", result.filename
      end
    end

    private

    def uploaded_file(name, type, body)
      file = Tempfile.new(name)
      file.write(body)
      file.rewind
      ActionDispatch::Http::UploadedFile.new(
        tempfile: file,
        filename: name,
        type: type
      )
    end
  end
end
