module AttendancesHelper
  def attendance_name_class(name)
    color = { 1 => 'blue', 2 => 'pink' }.fetch(name.gender, 'green')
    "attendance-name attendance-name--#{color}"
  end
end
