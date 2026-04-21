require 'csv'

file_path = 'sokhatsky.ged'

individuals = {}
families = {}

current_record = nil
current_record_type = nil
current_tag = nil

File.open(file_path, "rb").each_line do |line|
  line = line.force_encoding('UTF-8').scrub('?').strip
  next if line.empty?

  parts = line.split(" ", 3)
  level = parts[0].to_i
  tag_or_id = parts[1]
  value = parts[2]

  if level == 0
    if value == "INDI"
      current_record_type = :indi
      current_record = { id: tag_or_id, name: "", born_date: "", death_date: "", birth_place: "", famc: nil }
      individuals[tag_or_id] = current_record
    elsif value == "FAM"
      current_record_type = :fam
      current_record = { id: tag_or_id, husb: nil, wife: nil }
      families[tag_or_id] = current_record
    else
      current_record_type = nil
    end
  elsif current_record_type == :indi
    if level == 1
      current_tag = tag_or_id
      if tag_or_id == "NAME" && current_record[:name].empty?
        current_record[:name] = value ? value.gsub('/', '').strip : ""
      elsif tag_or_id == "FAMC" && current_record[:famc].nil?
        current_record[:famc] = value
      end
    elsif level == 2
      if current_tag == "BIRT" && tag_or_id == "DATE"
        current_record[:born_date] = value
      elsif current_tag == "BIRT" && tag_or_id == "PLAC"
        current_record[:birth_place] = value
      elsif current_tag == "DEAT" && tag_or_id == "DATE"
        current_record[:death_date] = value
      end
    end
  elsif current_record_type == :fam
    if level == 1
      if tag_or_id == "HUSB"
        current_record[:husb] = value
      elsif tag_or_id == "WIFE"
        current_record[:wife] = value
      end
    end
  end
end

root_id = individuals.keys.find { |id| individuals[id][:name] == "Максим Сохацький" }

if root_id.nil?
  puts "Error: Maksym Sokhatsky not found."
  exit 1
end

results = []

def traverse(id, depth, current_color, inds, fams, res)
  return if depth > 12
  person = inds[id]
  return unless person
  res << [ depth, current_color, person[:name], person[:born_date], person[:death_date], person[:birth_place]]
  famc = person[:famc]
  if famc && fams[famc]
    husb_id = fams[famc][:husb]
    wife_id = fams[famc][:wife]

    husb_color = current_color
    wife_color = current_color

    if depth == 0
      husb_color = "-1"
      wife_color = "-2"
    elsif depth == 1
      husb_color = current_color == "-1" ? "11" : "21"
      wife_color = current_color == "-1" ? "12" : "22"
    end
    traverse(husb_id, depth + 1, husb_color, inds, fams, res) if husb_id
    traverse(wife_id, depth + 1, wife_color, inds, fams, res) if wife_id
  end
end

traverse(root_id, 0, "Root", individuals, families, results)

csv_path = "sokhatsky_lineage.csv"
CSV.open(csv_path, "w") do |csv|
  csv << [ "Depth", "Color", "Fully Qualified Name", "Born Date", "Death Date", "Birth Place"]
  results.each do |row|
    csv << row
  end
end

puts "CSV generated successfully at #{csv_path} with #{results.size} records."
