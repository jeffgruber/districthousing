# Load information from all PDFs in public/forms that don't already
# exist in the database.  PDFs that are already in the database will be
# untouched, but PDFs not in the database will be added and given a name based
# on their filename.

require 'csv'
require 'open-uri'
require 'json'

def download_pdf uri, name, where
  # Download the file to the public/forms/ directory, and generate a path
  puts "Download #{name} from #{uri}"
  output_filename = "#{where}#{Slugify.slugify(name)}.pdf"
  system("wget #{uri} --output-document=#{output_filename}")
  output_filename
end

task seed_pdfs: :environment do
  puts "Seeding PDFs"

  HousingForm.transaction do
    FormField.transaction do
      # Add seed forms only if they don't already exist
      CSV.foreach(Rails.root.join("db","buildings.csv"), :headers => true) do |row|
        unless HousingForm.find_by(name: row['Property Name'])
          path = nil
          unless row['uri'].blank?
            path = download_pdf(row['uri'], row['name'], 'public/forms/stock/')
          end
          HousingForm.create(name: row['Property Name'], location: row['Property Address'], lat: row['lat'], long: row['lng'], path: path)
        end
      end
    end
  end
end

# Retrieve PDFs from districthousing.org.  Code for DC team members who work on
# editing PDFs for District Housing are encouraged to put their most up-to-date
# PDFs on districthousing.org, so the progress is visible, and other team
# members can easily try filling out the PDFs themselves.
#
# This task allows new deployments of District Housing (such as the one at Bread
# for the City) to retrieve the most up-to-date PDFs from districthousing.org to
# their local database.

task pull_pdfs: :environment do
  open('http://districthousing.org/housing_forms.json') do |housing_form_json|
    json = housing_form_json.read
    housing_forms = JSON.parse(json)
    housing_forms.each do |housing_form|
      # If the housing form was already pulled before, update it, unless someone
      # has uploaded a new form on the local instance.
      existing_form = HousingForm.find_by(remote_id: housing_form['id'])
      if existing_form and existing_form.updated_locally?
        puts "Ignoring updates due to local changes: #{existing_form['name']}".
          yellow
        next
      end

      # We use this hash to update the new housing form.  Don't go about
      # changing existing IDs!
      housing_form['remote_id'] = housing_form['id']
      housing_form.delete('id')

      unless housing_form['url'].blank?
        download_uri = "http://districthousing.org#{housing_form['url']}"
        housing_form['path'] = download_pdf(
          download_uri,
          housing_form['name'],
          'public/forms/')
      end

      # 'url' is not a HousingForm database field.  Remove it so we can use this
      # hash to update or create.
      housing_form.delete('url')

      if existing_form.nil?
        puts "New PDF: #{housing_form['name']}".green
        HousingForm.create(housing_form)
      else
        puts "Update PDF: #{existing_form['name']}".cyan
        existing_form.update(housing_form)
      end
    end
  end
end
