class InspectionFinding < ActiveRecord::Base
  belongs_to :inspection
  validates_uniqueness_of :label, :scope => :inspection_id
end
