require 'csv'
require 'fileutils'
require 'uri'
require 'open-uri'
require 'optparse'

options = { all: true, recursive: nil, deep: 3 }
OptionParser.new do |opts|
  opts.banner = "Usage: parse_sokhatsky.rb [options] [root_id]"

  opts.on("-a", "--all", "Sequential all one by one (default)") do
    options[:all] = true
  end

  opts.on("-r", "--recursive ID", "Recursive fetch starting from ID") do |id|
    options[:recursive] = id
    options[:all] = false
  end

  opts.on("-d", "--deep N", Integer, "Limit recursive fetch depth (default 3)") do |n|
    options[:deep] = n
  end

  opts.on("-p", "--publish ID", "Publish person page(s). Use 'all' for everyone in target list.") do |id|
    options[:publish] = id
    options[:all] = false unless id == 'all'
  end
end.parse!

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
      current_record = { id: tag_or_id, husb: nil, wife: nil, children: [], block: [] }
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
        elsif tag_or_id == "CHIL"
          current_record[:children] << value
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
param_root = options[:recursive] || ARGV[0]
if param_root
  param_root = "@#{param_root}@" unless param_root.start_with?("@")
end

root_id = if param_root && individuals[param_root]
            param_root
          else
            found = individuals.keys.find { |id| individuals[id][:name] == "Максим Сохацький" }
            found || individuals.keys.find { |id| individuals[id][:famc].nil? } || individuals.keys.first
          end

# Cluster discovery for recursive fetch
def find_cluster(start_id, max_depth, inds, fams)
  cluster = Set.new([start_id])
  current_level = [start_id]

  max_depth.times do
    next_level = []
    current_level.each do |id|
      person = inds[id]
      next unless person

      # Parents
      if person[:famc] && fams[person[:famc]]
        f = fams[person[:famc]]
        [f[:husb], f[:wife]].compact.each do |pid|
          unless cluster.include?(pid)
            cluster << pid
            next_level << pid
          end
        end
      end

      # Spouses and Children
      person[:fams].each do |fid|
        f = fams[fid]
        next unless f
        [f[:husb], f[:wife]].compact.concat(f[:children]).each do |pid|
          unless cluster.include?(pid)
            cluster << pid
            next_level << pid
          end
        end
      end
    end
    break if next_level.empty?
    current_level = next_level
  end
  cluster.to_a
end

require 'set'
target_ids = if options[:recursive]
               puts "Discovering recursive cluster for #{root_id} (deep: #{options[:deep]})..."
               find_cluster(root_id, options[:deep], individuals, families)
             elsif options[:publish] && options[:publish] != 'all'
               id = options[:publish]
               id = "@#{id}@" unless id.start_with?("@")
               [id]
             else
               individuals.keys
             end

puts "Root selected: #{root_id} (#{individuals[root_id][:name]})"
puts "Targeting #{target_ids.size} individuals..."

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

def generate_person_html(id, person, ancestors, person_dir, template)
  clean_id = id.gsub('@', '')
  
  # 1. Profile Photo
  profile_photo = "no-avatar.png"
  photos = []
  docs_a4 = []
  docs_a3 = []

  person[:objes].each_with_index do |obj, idx|
    next unless obj[:file]
    date = sanitize(obj[:date] || "unknown")
    titl = sanitize(obj[:titl] || "media_#{idx}")
    ext = (obj[:form] || File.extname(obj[:file] || "").delete('.')).downcase
    ext = "jpg" if ext.empty?
    ext = ext.split('?')[0] if ext.include?('?')
    
    is_doc = %w[pdf doc docx txt rtf].include?(ext) || titl.downcase =~ /metric|record|book|document|certificate|метрика|книга|свідоцтво/
    prefix = is_doc ? "document" : "image"
    filename = "#{prefix}-#{clean_id}-#{date}-#{titl}.#{ext}"
    
    if idx == 0 && !is_doc
      profile_photo = filename
    end
    
    if is_doc
      if titl.downcase.include?("a3")
        docs_a3 << { file: filename, title: obj[:titl] }
      else
        docs_a4 << { file: filename, title: obj[:titl] }
      end
    else
      photos << { file: filename, title: obj[:titl] }
    end
  end

  # 2. Ancestors Table
  sorted_ancestors = ancestors.sort_by { |a| [a[1].to_i, a[2].to_s] }
  ancestors_html = sorted_ancestors.map do |row|
    color_code = row[2].to_s
    flag_class = "flag-none"
    if color_code.start_with?("11")
      flag_class = "flag-blue"
    elsif color_code.start_with?("12")
      flag_class = "flag-green"
    elsif color_code.start_with?("21")
      flag_class = "flag-yellow"
    elsif color_code.start_with?("22")
      flag_class = "flag-red"
    end
    
    flag_html = color_code == "Root" || color_code == "-1" || color_code == "-2" ? "" : "<span class='lineage-flag #{flag_class}' title='#{color_code}'></span>"

    "<tr>
      <td>#{row[0]}</td>
      <td><span class='depth-indicator'>#{row[1]}</span></td>
      <td>#{flag_html}</td>
      <td><strong>#{row[3]}</strong></td>
      <td>#{row[4]}</td>
      <td>#{row[5]}</td>
      <td>#{row[6]}</td>
      <td><small>#{row[7]}</small></td>
    </tr>"
  end.join("\n")

  # 3. Life Events
  events = []
  events << { tag: "BORN", value: "#{person[:born_date]} #{person[:birth_place]}".strip } unless person[:born_date].to_s.empty? && person[:birth_place].to_s.empty?
  person[:events].each { |e| events << e unless e[:value].to_s.strip.empty? }
  events << { tag: "DEAT", value: person[:death_date] } unless person[:death_date].to_s.empty?
  
  events_html = events.map do |e|
    "<div class='event-card'>
      <div class='event-tag'>#{e[:tag]}</div>
      <div class='event-value'>#{e[:value]}</div>
    </div>"
  end.join("\n")

  # 4. Photo Gallery
  photos_html = photos.map do |p|
    "<div class='gallery-item'>
      <img src='#{p[:file]}' alt='#{p[:title]}'>
    </div>"
  end.join("\n")

  # 5. Documents
  docs_a4_html = docs_a4.map do |d|
    "<div class='doc-card'>
      <img src='#{d[:file]}' alt='#{d[:title]}'>
      <div class='doc-title'>#{d[:title]}</div>
    </div>"
  end.join("\n")

  docs_a3_html = docs_a3.map do |d|
    "<div class='doc-card'>
      <img src='#{d[:file]}' alt='#{d[:title]}'>
      <div class='doc-title'>#{d[:title]}</div>
    </div>"
  end.join("\n")

  # Replace placeholders
  html = template.dup
  html.gsub!("{{NAME}}", person[:name])
  html.gsub!("{{DATES}}", "#{person[:born_date]} — #{person[:death_date]}")
  html.gsub!("{{PROFILE_PHOTO}}", profile_photo)
  html.gsub!("{{BIOGRAPHY}}", person[:notes].join("\n\n"))
  html.gsub!("{{ANCESTORS_TABLE}}", ancestors_html)
  html.gsub!("{{EVENTS_LIST}}", events_html)
  html.gsub!("{{PHOTO_GALLERY}}", photos_html)
  html.gsub!("{{DOCUMENTS_A4}}", docs_a4_html)
  html.gsub!("{{DOCUMENTS_A3}}", docs_a3_html)

  File.write(File.join(person_dir, "index.html"), html)
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

# Prepare publishing
publish_template = nil
if options[:publish]
  template_path = File.join('assets', 'templates', 'person.html')
  if File.exist?(template_path)
    publish_template = File.read(template_path)
  else
    puts "Warning: Template not found at #{template_path}"
  end
end

puts "Processing #{target_ids.size} individuals..."
full_results = []

# To avoid creating 38k folders at once, you might want to throttle or just proceed.
# We will create folders for everyone in the target list.
target_ids.each do |id|
  person = individuals[id]
  next unless person
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

  # HTML Generation
  if options[:publish] == 'all' || options[:publish] == clean_id || options[:publish] == id
    if publish_template
      generate_person_html(id, person, sub_res, person_dir, publish_template)
    end
  end
end

main_csv_path = File.join(PRIV_DIR, "sokhatsky_familysearch.csv")
write_csv(main_csv_path, ["Id", "Depth", "Color", "Fully Qualified Name", "Born Date", "Death Date", "Birth Place", "Other Info"], full_results)

puts "Complete. Processed #{target_ids.size} people into #{PRIV_DIR}/"
