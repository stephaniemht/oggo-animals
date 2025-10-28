require "test_helper"

class Admin::ProfessionMappingsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_profession_mappings_index_url
    assert_response :success
  end
end
