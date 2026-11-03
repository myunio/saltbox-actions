class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include Saltbox::Actions::ChangeTracking
end
