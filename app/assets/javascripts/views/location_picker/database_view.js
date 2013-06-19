chorus.views.LocationPicker.DatabaseView = chorus.views.LocationPicker.SelectorView.extend({
    templateName: "location_picker_database",
    constructorName: "LocationPickerDatabaseView",

    events: {
        "change select": "databaseSelected"
    },

    setup: function() {
        this.childPicker = this.options.childPicker;
        this.setState(this.options.database ? this.STATES.STATIC : this.STATES.LOADING);
    },

    additionalContext: function() {
        return {
            allowCreate: this.options.allowCreate,
            database: this.options.database
        };
    },

    parentSelected: function(dataSource) {
        this.clearSelection();
        this.childPicker && this.childPicker.clearSelection();
        if (dataSource) {
            this.setState(this.STATES.LOADING);
            this.fetchDatabases(dataSource);
        }
    },

    onFetchFailed: function() {
        this.clearSelection();
    },

    fetchDatabases: function(selectedDataSource) {
        this.collection = selectedDataSource.databases();
        this.collection.fetchAllIfNotLoaded();
        this.listenTo(this.collection, "fetchFailed", this.fetchFailed);
        this.onceLoaded(this.collection, this.databasesLoaded);
    },

    databasesLoaded: function() {
        if (this.stateValue !== this.STATES.HIDDEN) {
            var state = (this.collection.length === 0) ? this.STATES.UNAVAILABLE : this.STATES.SELECT;
            this.setState(state);
        }
    },

    databaseSelected: function() {
        this.trigger("clearErrors");
        this.childPicker && this.childPicker.clearSelection();
        var selectedDatabase = this.getSelectedDatabase();

        if(selectedDatabase) {
            this.selection = selectedDatabase;
            if (this.childPicker) {
                this.childPicker.setState(this.STATES.LOADING);
                this.childPicker.fetchSchemas(selectedDatabase);
            }
        } else {
            this.clearSelection();
            this.childPicker && this.childPicker.hide();
        }
        this.trigger('change');
    },

    fieldValues: function() {
        var attrs = {};
        if(this.selection && this.selection.get('id')) {
            attrs.database = this.selection.get("id");
        } else if(this.selection && this.selection.get("name")) {
            attrs.databaseName = this.selection.get('name');
        } else {
            attrs.databaseName = this.$("input.name:visible").val();
        }
        return attrs;
    },

    getSelectedDatabase: function() {
        return this.collection && this.collection.get(this.$('select option:selected').val());
    },

    ready: function() {
        var attrs = this.fieldValues();
        return !!(attrs.database || attrs.databaseName);
    }
});