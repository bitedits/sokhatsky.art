require 'csv'
require 'fileutils'
require 'optparse'
require 'pathname'

options = { all: true, recursive: nil, publish: nil, epoc: 'priv', epoc_out: nil, index: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: genie_sokhatsky.rb [options]"

  opts.on("-a", "--all", "Publish all one by one (default)") do
    options[:all] = true
  end

  opts.on("-p", "--publish ID", "Publish specific person ID") do |id|
    options[:publish] = id
    options[:all] = false
  end

  opts.on("-g", "--gedcom FILENAME", "Repack storage into a GEDCOM file") do |file|
    options[:gedcom] = file
  end

  opts.on("-e", "--epoc DIR", "Prefix directory for storage/static (default: priv)") do |dir|
    options[:epoc] = dir
  end

  opts.on("--epoc-out DIR", "Output top level folder for static files (overrides --epoc)") do |dir|
    options[:epoc_out] = dir
  end

  opts.on("--index DIR", "Generate index.html in the specified folder") do |dir|
    options[:index] = dir
  end
end.parse!

STORAGE_DIR = File.join(options[:epoc], 'storage')
STATIC_DIR = File.join(options[:epoc_out] || options[:epoc], 'static')
FileUtils.mkdir_p(STATIC_DIR)

TEMPLATE_PATH = File.join('assets', 'templates', 'person.html')
unless File.exist?(TEMPLATE_PATH)
  puts "Error: Template not found at #{TEMPLATE_PATH}"
  exit 1
end
TEMPLATE = File.read(TEMPLATE_PATH)

def read_csv(path)
  return [] unless File.exist?(path)
  CSV.read(path, headers: true).map(&:to_h)
end

def generate_html(folder_name, storage_path, static_path)
  clean_id = folder_name.split('-').first
  
  # Read data
  indi_data = Hash[read_csv(File.join(storage_path, "indi-#{clean_id}.csv")).map { |r| [r["Field"], r["Value"]] }]
  events_data = read_csv(File.join(storage_path, "events-#{clean_id}.csv"))
  ancestors_data = read_csv(File.join(storage_path, "#{clean_id}.csv"))
  multimedia_data = read_csv(File.join(storage_path, "multimedia-#{clean_id}.csv"))
  bio = File.exist?(File.join(storage_path, "bio-#{clean_id}.txt")) ? File.read(File.join(storage_path, "bio-#{clean_id}.txt")) : ""

  # 1. Profile Photo
  assets_path = Pathname.new("assets")
  static_page_dir = Pathname.new(static_path)
  no_avatar_path = assets_path.join("img", "no-avatar.png")
  profile_photo = no_avatar_path.relative_path_from(static_page_dir).to_s
  photos_html = []
  docs_a4_html = []
  docs_a3_html = []

  # Find physical files in storage
  files = Dir.glob(File.join(storage_path, "*")).map { |f| File.basename(f) }
  
  # Map files to HTML
  files.each_with_index do |filename, idx|
    next if filename.end_with?(".csv") || filename.end_with?(".txt") || filename.end_with?(".ged") || filename == "index.html"
    
    # Calculate relative path from static page to storage asset
    static_page_dir = Pathname.new(File.join(static_path))
    storage_asset_path = Pathname.new(File.join(storage_path, filename))
    relative_path = storage_asset_path.relative_path_from(static_page_dir).to_s
    
    is_doc = filename.start_with?("document")
    titl = filename.split('-').last.split('.').first.gsub('_', ' ')

    if is_doc
      html = "<div class='doc-card'>
                <img src='#{relative_path}' alt='#{titl}'>
                <div class='doc-title'>#{titl}</div>
              </div>"
      if filename.downcase.include?("a3")
        docs_a3_html << html
      else
        docs_a4_html << html
      end
    else
      photos_html << "<div class='gallery-item'><img src='#{relative_path}' alt='#{titl}'></div>"
    end
  end

  # Select Profile Photo: find image with shortest suffix (image-ID-SUFFIX.EXT)
  all_images = files.select { |f| f.start_with?("image-#{clean_id}") }
  unless all_images.empty?
    best_image = all_images.min_by { |f| f.gsub(/^image-#{clean_id}-/, '').split('.').first.length }
    storage_asset_path = Pathname.new(File.join(storage_path, best_image))
    profile_photo = storage_asset_path.relative_path_from(static_page_dir).to_s
  end

  # 2. Ancestors Table
  # CSV headers: Id, Depth, Color, Fully Qualified Name, Born Date, Death Date, Birth Place, Other Info
  sorted_ancestors = ancestors_data.sort_by { |a| [a["Depth"].to_i, a["Color"].to_s] }
  ancestors_html = sorted_ancestors.map do |row|
    color_code = row["Color"].to_s
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
      <td>#{row['Id']}</td>
      <td><span class='depth-indicator'>#{row['Depth']}</span></td>
      <td>#{flag_html}</td>
      <td><strong>#{row['Fully Qualified Name']}</strong></td>
      <td>#{row['Born Date']}</td>
      <td>#{row['Death Date']}</td>
      <td>#{row['Birth Place']}</td>
      <td><small>#{row['Other Info']}</small></td>
    </tr>"
  end.join("\n")

  # 3. Life Events
  events = []
  events << { tag: "BORN", value: "#{indi_data['Born Date']} #{indi_data['Birth Place']}".strip } unless indi_data['Born Date'].to_s.empty? && indi_data['Birth Place'].to_s.empty?
  events_data.each { |e| events << { tag: e['Tag'], value: "#{e['Value']} #{e['Date']} #{e['Place']}".strip } unless e['Value'].to_s.empty? && e['Date'].to_s.empty? }
  events << { tag: "DEAT", value: indi_data['Death Date'] } unless indi_data['Death Date'].to_s.empty?
  
  events_html = events.map do |e|
    "<div class='event-card'>
      <div class='event-tag'>#{e[:tag]}</div>
      <div class='event-value'>#{e[:value]}</div>
    </div>"
  end.join("\n")

  # Replace placeholders
  html = TEMPLATE.dup
  
  # Calculate relative path to assets root
  assets_root = Pathname.new("assets")
  assets_rel = assets_root.relative_path_from(static_page_dir).to_s
  
  html.gsub!("{{ASSETS_PATH}}", assets_rel)
  html.gsub!("{{NAME}}", indi_data["Name"] || clean_id)
  html.gsub!("{{DATES}}", "#{indi_data['Born Date']} — #{indi_data['Death Date']}")
  html.gsub!("{{PROFILE_PHOTO}}", profile_photo)
  
  # Hide empty sections
  def replace_section(html, id, content, placeholder)
    if content.to_s.strip.empty?
      html.gsub!(/<section id="#{id}">.*?<\/section>/m, "")
    else
      html.gsub!(placeholder, content)
    end
  end

  replace_section(html, "biography", bio.to_s.gsub("\n", "<br>"), "{{BIOGRAPHY}}")
  replace_section(html, "ancestors", ancestors_html, "{{ANCESTORS_TABLE}}")
  replace_section(html, "events", events_html, "{{EVENTS_LIST}}")
  replace_section(html, "photos", photos_html.join("\n"), "{{PHOTO_GALLERY}}")
  
  # Special case for documents: combine A4 and A3 check
  if docs_a4_html.empty? && docs_a3_html.empty?
    html.gsub!(/<section id="documents">.*?<\/section>/m, "")
  else
    html.gsub!("{{DOCUMENTS_A4}}", docs_a4_html.join("\n"))
    html.gsub!("{{DOCUMENTS_A3}}", docs_a3_html.join("\n"))
  end

  FileUtils.mkdir_p(static_path)
  File.write(File.join(static_path, "index.html"), html)
end

def format_gedcom_note(text, newline = "\n")
  return "" if text.to_s.strip.empty?
  lines = text.split(/\r?\n/)
  result = "1 NOTE #{lines.shift}#{newline}"
  lines.each do |line|
    result << "2 CONT #{line}#{newline}"
  end
  result
end

def repack_gedcom(output_path)
  puts "Repacking storage into #{output_path}..."
  gedcom_content = ""
  
  # 1. Header
  header_path = File.join(STORAGE_DIR, "header.ged")
  if File.exist?(header_path)
    gedcom_content << File.read(header_path)
  else
    gedcom_content << "0 HEAD\n1 CHAR UTF-8\n"
  end
  
  # 2. Individual Records (INDI)
  puts "Collecting individuals..."
  Dir.glob(File.join(STORAGE_DIR, "*", "raw-*.ged")).sort.each do |f|
    clean_id = File.basename(f).split('-').last.split('.').first
    person_dir = File.dirname(f)
    bio_path = File.join(person_dir, "bio-#{clean_id}.txt")
    
    content = File.read(f).force_encoding('UTF-8').scrub('?')
    
    if File.exist?(bio_path)
      # Detect newline style
      newline = content.include?("\r\n") ? "\r\n" : "\n"
      
      # Replace existing NOTE blocks with edited bio
      content.gsub!(/^1 NOTE.*?\r?\n(^[2-9] (CONT|CONC).*?\r?\n)*/m, "")
      # Insert new bio after the level 0 line
      content.sub!(/^(0 @.*?@ INDI\r?\n)/, "\\1#{format_gedcom_note(File.read(bio_path), newline)}")
    end
    
    gedcom_content << content
  end
  
  # 3. Global Records (FAM, SOUR, etc.)
  puts "Collecting families and sources..."
  Dir.glob(File.join(STORAGE_DIR, "raw-*.ged")).sort.each do |f|
    gedcom_content << File.read(f)
  end
  
  # 4. Trailer
  gedcom_content << "0 TRLR\n"
  
  File.write(output_path, gedcom_content)
  puts "Repack complete: #{output_path} (#{File.size(output_path)} bytes)"
end

def generate_index(output_dir, folders)
  puts "Generating index in #{output_dir}..."
  index_template_path = File.join('assets', 'templates', 'index.html')
  return puts "Error: Index template not found" unless File.exist?(index_template_path)
  template = File.read(index_template_path)
  
  people_data = []
  
  folders.each do |folder|
    clean_id = folder.split('-').first
    storage_path = File.join(STORAGE_DIR, folder)
    indi_csv = File.join(storage_path, "indi-#{clean_id}.csv")
    next unless File.exist?(indi_csv)
    
    indi_data = Hash[read_csv(indi_csv).map { |r| [r["Field"], r["Value"]] }]
    
    # Heuristic for sorting and grouping
    full_name = indi_data["Name"] || clean_id
    surname = full_name.split(' ').last || ""
    first_letter = surname.strip[0] || full_name.strip[0] || "?"
    
    year = indi_data['Born Date'].to_s.scan(/\d{4}/).first || "9999"
    
    # Calculate relative link from index page to person page
    index_dir = Pathname.new(output_dir)
    person_page_path = Pathname.new(File.join(STATIC_DIR, folder, "index.html"))
    rel_link = person_page_path.relative_path_from(index_dir).to_s
    
    people_data << {
      id: clean_id,
      name: full_name,
      surname: surname,
      first_letter: first_letter.upcase,
      dates: "#{indi_data['Born Date']} — #{indi_data['Death Date']}",
      born_sort: year,
      link: rel_link
    }
  end
  
  # Group by letter
  grouped = people_data.group_by { |p| p[:first_letter] }.sort
  
  index_html = ""
  grouped.each do |letter, members|
    # Sort members historically (chronologically)
    sorted_members = members.sort_by { |m| m[:born_sort] }
    
    index_html << "<section class='letter-section'>\n"
    index_html << "  <div class='letter-header'>#{letter}</div>\n"
    index_html << "  <div class='entry-list'>\n"
    sorted_members.each do |m|
      index_html << "    <a href='#{m[:link]}' class='entry-item'>\n"
      index_html << "      <span class='name'>#{m[:name]}</span>\n"
      index_html << "      <span class='dates'>#{m[:dates]}</span>\n"
      index_html << "    </a>\n"
    end
    index_html << "  </div>\n"
    index_html << "</section>\n"
  end
  
  # Calculate relative path to assets root from the index page
  assets_root = Pathname.new("assets")
  static_page_dir = Pathname.new(output_dir)
  assets_rel = assets_root.relative_path_from(static_page_dir).to_s
  
  final_html = template.gsub("{{INDEX_CONTENT}}", index_html)
  final_html.gsub!("{{ASSETS_PATH}}", assets_rel)
  
  FileUtils.mkdir_p(output_dir)
  File.write(File.join(output_dir, "index.html"), final_html)
  puts "Index complete: #{output_dir}/index.html"
end

# Main Execution
if options[:gedcom]
  repack_gedcom(options[:gedcom])
  exit 0
end

folders = Dir.entries(STORAGE_DIR).select { |entry| File.directory?(File.join(STORAGE_DIR, entry)) && !(entry =='.' || entry == '..') }

if options[:publish]
  target_id = options[:publish].gsub('@', '')
  folders = folders.select { |f| f.start_with?(target_id) }
end

puts "Generating static pages for #{folders.size} individuals..."

folders.each do |folder|
  storage_path = File.join(STORAGE_DIR, folder)
  static_path = File.join(STATIC_DIR, folder)
  generate_html(folder, storage_path, static_path)
end

puts "Static site generation complete in #{STATIC_DIR}/"

if options[:index]
  # Refresh folders list to include all for index
  all_folders = Dir.entries(STORAGE_DIR).select { |entry| File.directory?(File.join(STORAGE_DIR, entry)) && !(entry =='.' || entry == '..') }
  generate_index(options[:index], all_folders)
end
