class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist
  self.table_name = "jwt_denylist"

  scope :expired, -> { where("exp < ?", Time.current) }
end
