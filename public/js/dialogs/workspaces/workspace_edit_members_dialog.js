;
(function(ns) {
    ns.dialogs.WorkspaceEditMembers = ns.dialogs.Base.extend({
        className : "workspace_edit_members",
        title: t("workspace.edit_members.title"),
        persistent: true,

        events : {
            "click button.submit" : "updateMembers"
        },

        makeModel : function () {
            this.collection = new chorus.models.UserSet();
            this.collection.fetchAll();
            this.members = this.options.pageModel.members();
            this.members.loaded || this.members.fetch();
        },

        setup : function() {
            this.shuttle = new ns.views.ShuttleWidget({
                collection : this.collection,
                selectionSource : this.members,
                objectName : t("workspace.members")
            });
        },

        postRender : function() {
            this.$(".shuttle").html(this.shuttle.render().el);
            this.shuttle.delegateEvents();
        },

        updateMembers : function() {

        }
    });
})(chorus)