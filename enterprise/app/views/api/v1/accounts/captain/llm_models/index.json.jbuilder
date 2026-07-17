json.models @models do |entry|
  json.value entry['value']
  json.label entry['label']
  json.provider_label entry['provider_label']
end
json.source @source
