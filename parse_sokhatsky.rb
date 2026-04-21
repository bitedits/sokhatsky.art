require 'csv'
require 'fileutils'
require 'uri'
require 'open-uri'

file_path = 'sokhatsky.ged'
PRIV_DIR = 'priv'
FileUtils.mkdir_p(PRIV_DIR)

individuals = {}
families = {}
sources = {}
head_block = []

current_record = nil
current_record_type = nil
current_tag = nil
current_block_type = nil
current_block = []

current_note = nil
current_obje = nil

puts "Parsing big GEDCOM file (#{file_path}) - 38k records..."

File.open(file_path, "rb").each_line do |line|
  orig_line = line
  line = line.force_encoding('UTF-8').scrub('?').strip
  next if line.empty?

  parts = line.split(" ", 3)
  level = parts[0].to_i
  tag_or_id = parts[1]
  value = parts[2]

  if level == 0
    if current_block_type == :indi && current_record
      current_record[:block] = current_block.dup
    elsif current_block_type == :fam && current_record
      current_record[:block] = current_block.dup
    elsif current_block_type == :head
      head_block = current_block.dup
    end
    
    current_block.clear
    current_block << orig_line
    current_note = nil
    current_obje = nil

    if value == "INDI"
      current_block_type = :indi
      current_record_type = :indi
      current_record = { 
        id: tag_or_id, name: "", given_name: "", surname: "", 
        born_date: "", death_date: "", 
        birth_place: "", famc: nil, fams: [], objes: [], notes: [],
        events: [], email: nil, married_name: nil, source_refs: []
      }
      individuals[tag_or_id] = current_record
    elsif value == "FAM"
      current_block_type = :fam
      current_record_type = :fam
      current_record = { id: tag_or_id, husb: nil, wife: nil, block: [] }
      families[tag_or_id] = current_record
    elsif value == "SOUR"
      current_block_type = :sour
      current_record_type = :sour
      current_record = { id: tag_or_id, title: "", text: "" }
      sources[tag_or_id] = current_record
    elsif tag_or_id == "HEAD"
      current_block_type = :head
      current_record_type = nil
    else
      current_block_type = :other
      current_record_type = nil
    end
  else
    current_block << orig_line

    if current_record_type == :indi
      if level == 1
        current_tag = tag_or_id
        if tag_or_id == "NAME" && current_record[:name].empty?
          current_record[:name] = value ? value.gsub('/', '').strip : ""
          if value && value =~ /\/(.*)\//
            current_record[:surname] = $1.strip if current_record[:surname].empty?
            current_record[:given_name] = value.gsub(/\/(.*)\//, '').strip if current_record[:given_name].empty?
          elsif value
            current_record[:given_name] = value.strip if current_record[:given_name].empty?
          end
        elsif tag_or_id == "FAMC" && current_record[:famc].nil?
          current_record[:famc] = value
        elsif tag_or_id == "FAMS"
          current_record[:fams] << value
        elsif tag_or_id == "SOUR"
          current_record[:source_refs] << value if value
        elsif tag_or_id == "OBJE"
          current_obje = { file: nil, form: nil, titl: nil, date: nil }
          current_record[:objes] << current_obje
        elsif tag_or_id == "NOTE"
          current_note = value ? value.dup : ""
          current_record[:notes] << current_note
        elsif ["OCCU", "EDUC", "EVEN", "BURI", "CHR", "RELI", "RESI"].include?(tag_or_id)
          current_record[:events] << { tag: tag_or_id, value: value }
        end
      elsif level == 2
        if tag_or_id == "GIVN"
          current_record[:given_name] = value
        elsif tag_or_id == "SURN"
          current_record[:surname] = value
        elsif tag_or_id == "DATE" && current_tag == "BIRT"
          current_record[:born_date] = value
        elsif tag_or_id == "PLAC" && current_tag == "BIRT"
          current_record[:birth_place] = value
        elsif tag_or_id == "DATE" && current_tag == "DEAT"
          current_record[:death_date] = value
        elsif current_tag == "NAME" && tag_or_id == "_MARNM"
          current_record[:married_name] = value
        elsif current_tag == "RESI" && tag_or_id == "EMAIL"
          current_record[:email] = value
        elsif current_tag == "OBJE"
          if tag_or_id == "FILE"
            current_obje[:file] = value
          elsif tag_or_id == "FORM"
            current_obje[:form] = value
          elsif tag_or_id == "TITL"
            current_obje[:titl] = value
          elsif tag_or_id == "_DATE"
            current_obje[:date] = value
          end
        elsif current_tag == "NOTE"
          if tag_or_id == "CONT"
            current_note << "\n" << (value || "")
          elsif tag_or_id == "CONC"
            current_note << (value || "")
          end
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
    elsif current_record_type == :sour
      if level == 1
        current_tag = tag_or_id
        if tag_or_id == "TITL"
          current_record[:title] = value
        elsif tag_or_id == "TEXT"
          current_record[:text] = value
        end
      elsif level == 2
        if current_tag == "TEXT"
           current_record[:text] << "\n" << (value || "")
        end
      end
    end
  end
end

if current_block_type == :indi && current_record
  current_record[:block] = current_block.dup
elsif current_block_type == :fam && current_record
  current_record[:block] = current_block.dup
end

# Root determination
param_root = ARGV[0]
if param_root
  param_root = "@#{param_root}@" unless param_root.start_with?("@")
end

root_id = if param_root && individuals[param_root]
            param_root
          else
            found = individuals.keys.find { |id| individuals[id][:name] == "Максим Сохацький" }
            found || individuals.keys.find { |id| individuals[id][:famc].nil? } || individuals.keys.first
          end

puts "Root selected: #{root_id} (#{individuals[root_id][:name]})"

# Ancestral relationship map for the main CSV
ancestor_info = {}
def map_ancestors(id, depth, color, inds, fams, map)
  return if depth > 12 || map[id]
  person = inds[id]
  return unless person
  map[id] = { depth: depth, color: color }
  famc = person[:famc]
  if famc && fams[famc]
    h, w = fams[famc][:husb], fams[famc][:wife]
    hc, wc = color, color
    if depth == 0
      hc, wc = "-1", "-2"
    elsif depth == 1
      hc = (color == "-1" ? "11" : "21")
      wc = (color == "-1" ? "12" : "22")
    end
    map_ancestors(h, depth + 1, hc, inds, fams, map) if h
    map_ancestors(w, depth + 1, wc, inds, fams, map) if w
  end
end

puts "Mapping main ancestral branch..."
map_ancestors(root_id, 0, "Root", individuals, families, ancestor_info)

def download_file(url, path)
  return if File.exist?(path)
  begin
    URI.open(url) do |image|
      File.open(path, 'wb') { |f| f.write(image.read) }
    end
  rescue
  end
end

def write_csv(csv_path, headers, rows)
  CSV.open(csv_path, "w") do |csv|
    csv << headers
    rows.each { |row| csv << row }
  end
end

def format_info(person)
  parts = []
  parts << "Married Name: #{person[:married_name]}" if person[:married_name]
  parts << "Email: #{person[:email]}" if person[:email]
  person[:events].each do |e|
    val = e[:value] && !e[:value].empty? ? ": #{e[:value]}" : ""
    parts << "#{e[:tag]}#{val}"
  end
  parts.join("; ")
end

def sanitize(str)
  res = str.to_s.gsub(/[^\w\p{Cyrillic}.]/, '_')
  res.gsub(/_+/, '_').gsub(/^_+|_+$/, '')
end

def get_folder_name(id, person)
  clean_id = id.gsub('@', '')
  return clean_id if person[:given_name].to_s.empty? && person[:surname].to_s.empty?
  g = sanitize(person[:given_name])
  s = sanitize(person[:surname].upcase)
  folder = clean_id
  folder += "-#{g}" unless g.empty?
  folder += "-#{s}" unless s.empty?
  folder
end

# Main traversal for a single person's CSV
def get_ancestors_list(id, depth, color, inds, fams, list)
  return if depth > 12
  person = inds[id]
  return unless person
  list << [ id.gsub('@',''), depth, color, person[:name], person[:born_date], person[:death_date], person[:birth_place], format_info(person)]
  famc = person[:famc]
  if famc && fams[famc]
    h, w = fams[famc][:husb], fams[famc][:wife]
    hc, wc = color, color
    if depth == 0
      hc, wc = "-1", "-2"
    elsif depth == 1
      hc = (color == "-1" ? "11" : "21")
      wc = (color == "-1" ? "12" : "22")
    end
    get_ancestors_list(h, depth + 1, hc, inds, fams, list) if h
    get_ancestors_list(w, depth + 1, wc, inds, fams, list) if w
  end
end

puts "Processing all #{individuals.size} individuals..."
full_results = []

# To avoid creating 38k folders at once, you might want to throttle or just proceed.
# We will create folders for everyone.
individuals.each do |id, person|
  clean_id = id.gsub('@', '')
  
  # Main CSV row
  rel = ancestor_info[id]
  depth = rel ? rel[:depth] : "N/A"
  color = rel ? rel[:color] : "N/A"
  full_results << [ clean_id, depth, color, person[:name], person[:born_date], person[:death_date], person[:birth_place], format_info(person) ]

  # Folder naming - FLAT hierarchy in priv/
  folder_name = get_folder_name(id, person)
  person_dir = File.join(PRIV_DIR, folder_name)
  FileUtils.mkdir_p(person_dir)
  
  # Extraction
  File.write(File.join(person_dir, "bio-#{clean_id}.txt"), person[:notes].join("\n\n")) unless person[:notes].empty?
  
  # Events
  unless person[:events].empty? && !person[:married_name] && !person[:email]
    lines = []
    lines << "Married Name: #{person[:married_name]}" if person[:married_name]
    lines << "Email: #{person[:email]}" if person[:email]
    person[:events].each { |e| lines << "#{e[:tag]}: #{e[:value]}" }
    File.write(File.join(person_dir, "events-#{clean_id}.txt"), lines.join("\n"))
    
    csv_rows = []
    csv_rows << ["Married Name", person[:married_name]] if person[:married_name]
    csv_rows << ["Email", person[:email]] if person[:email]
    person[:events].each { |e| csv_rows << [e[:tag], e[:value]] }
    write_csv(File.join(person_dir, "events-#{clean_id}.csv"), ["Attribute", "Value"], csv_rows)
  end
  
  # Sources
  unless person[:source_refs].empty?
    s_lines = person[:source_refs].map do |s_id|
       s = sources[s_id]
       s ? "Source #{s_id}: #{s[:title]} #{s[:text]}" : "Source #{s_id}"
    end
    File.write(File.join(person_dir, "sources-#{clean_id}.txt"), s_lines.join("\n"))
  end
  
  # Multimedia
  person[:objes].each_with_index do |obj, idx|
    next unless obj[:file]
    date = sanitize(obj[:date] || "unknown")
    titl = sanitize(obj[:titl] || "media_#{idx}")
    ext = (obj[:form] || File.extname(obj[:file] || "").delete('.')).downcase
    ext = "jpg" if ext.empty?
    ext = ext.split('?')[0] if ext.include?('?')
    prefix = %w[pdf doc docx txt rtf].include?(ext) ? "document" : "image"
    download_file(obj[:file], File.join(person_dir, "#{prefix}-#{clean_id}-#{date}-#{titl}.#{ext}")) if obj[:file].start_with?('http')
  end
  
  # Sub-tree CSV (Ancestor tree for THIS person)
  sub_csv = File.join(person_dir, "#{clean_id}.csv")
  sub_res = []
  get_ancestors_list(id, 0, "Root", individuals, families, sub_res)
  write_csv(sub_csv, ["Id", "Depth", "Color", "Fully Qualified Name", "Born Date", "Death Date", "Birth Place", "Other Info"], sub_res)
end

main_csv_path = File.join(PRIV_DIR, "sokhatsky_familysearch.csv")
write_csv(main_csv_path, ["Id", "Depth", "Color", "Fully Qualified Name", "Born Date", "Death Date", "Birth Place", "Other Info"], full_results)

puts "Complete. Processed #{individuals.size} people into #{PRIV_DIR}/"
