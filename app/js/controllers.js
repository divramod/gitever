'use strict';

/* Controllers */


function NoteListCtrl($scope, $http) {
    $scope.notes = "Laden";
    $scope.fetch = function(event) {
        console.log (event);

        $scope.code = null;
        $scope.response = null;

        $http({method: "GET", url: "/notes/all"}).
            success(function(data, status) {
                $scope.status = status;
                $scope.notes = data;
            }).
            error(function(data, status) {
                $scope.notes = data || "Request failed";
                $scope.status = status;
            });
    };

    $scope.$on('dataDemanded', $scope.fetch(event));
}
//MyCtrl1.$inject = [];


function NoteDetailCtrl($scope, $routeParams, $http) {

    //$scope.note.id = $routeParams.noteId;
    $scope.fetchNote = function($routeParams) {

        $scope.url = "/notes/" + $routeParams.noteId;
        $http({method: "GET", url: $scope.url}).
            success(function(data, status) {
                $scope.status = status;
                $scope.note = data;
            }).
            error(function(data, status) {
                $scope.note = data || "Request failed";
                $scope.status = status;
            });
    };
    $scope.note = $scope.fetchNote($routeParams);
}
//MyCtrl2.$inject = [];
