Imports System
Imports System.Data
Imports System.Data.SqlClient
Imports System.Data.SqlTypes
Imports Microsoft.SqlServer.Server
Imports System.ComponentModel
Imports System.IO
Imports System.Xml
Imports System.Text
Imports System.Security.Cryptography

Public Class SYL
    Private Const m_ConString As String = "context connection=true"

    Private Enum AutheticationMethods As Byte
        SQLAuthentication = 0
        WindowsAuthentication = 1
    End Enum

    Private Shared Function BuildConnectionString(ByVal Servername As String, _
                                                ByVal AuthenticationType As AutheticationMethods, _
                                                ByVal SqlLogin As String, _
                                                ByVal SqlPassword As String, _
                                                Optional ByVal DatabaseName As String = "master") As String

        Dim csc As New SqlConnectionStringBuilder
        Try
            With csc
                .DataSource = Servername
                .InitialCatalog = DatabaseName
                .IntegratedSecurity = (AuthenticationType <> AutheticationMethods.SQLAuthentication)
                If Not .IntegratedSecurity Then
                    .UserID = SqlLogin
                    .Password = SqlPassword
                End If
                .ApplicationName = "SYL 2005"
                Return .ConnectionString
            End With
        Catch Exp As Exception
            Throw Exp
        End Try
    End Function

    Private Shared Function ConvertTypeToSQLDataType(ByVal theType As System.Type) As SqlDbType
        Dim param As SqlParameter
        Dim tc As TypeConverter
        param = New SqlParameter()
        tc = TypeDescriptor.GetConverter(param.DbType)
        If theType.ToString = "System.Byte[]" Then
            param.DbType = DbType.Binary
        ElseIf theType.ToString = "System.Int32" Then
            param.DbType = DbType.Int64
        ElseIf (tc.CanConvertFrom(theType)) Then
            param.DbType = CType(tc.ConvertFrom(theType.Name), DbType)
        Else
            Try
                param.DbType = CType(tc.ConvertFrom(theType.Name), DbType)
            Catch e As Exception
            End Try
        End If
        Return param.SqlDbType
    End Function

    Private Shared Function GetTableSchema(ByVal tbl As DataTable) As Collections.Generic.List(Of SqlMetaData)
        Dim dbType As SqlDbType
        Dim OutputColumn As SqlMetaData
        Dim OutputColumns As New Collections.Generic.List(Of SqlMetaData)
        For Each col As DataColumn In tbl.Columns
            dbType = ConvertTypeToSQLDataType(col.DataType)
            If dbType = SqlDbType.Binary Or dbType = SqlDbType.Image Or dbType = SqlDbType.NText _
                        Or dbType = SqlDbType.NVarChar Or dbType = SqlDbType.Text Or dbType = SqlDbType.Udt _
                        Or dbType = SqlDbType.VarBinary Or dbType = SqlDbType.VarChar Or dbType = SqlDbType.Variant _
                        Or dbType = SqlDbType.Xml Then
                OutputColumn = New SqlMetaData(col.ColumnName, ConvertTypeToSQLDataType(col.DataType), col.MaxLength)
                'SqlContext.Pipe.Send("," & col.ColumnName & " -- " & col.DataType.ToString & " - " & ConvertTypeToSQLDataType(col.DataType).ToString + "(" + col.MaxLength.ToString + ")")
            Else
                OutputColumn = New SqlMetaData(col.ColumnName, ConvertTypeToSQLDataType(col.DataType))
                'SqlContext.Pipe.Send("," & col.ColumnName & " --     " & col.DataType.ToString & " - " & ConvertTypeToSQLDataType(col.DataType).ToString)
            End If
            OutputColumns.Add(OutputColumn)
        Next
        Return OutputColumns
    End Function

    Private Shared Sub SendDataTableOverPipe(ByVal tbl As DataTable, ByVal record As SqlDataRecord)
        For Each row As DataRow In tbl.Rows
            For col As Integer = 0 To tbl.Columns.Count - 1
                record.SetValue(col, row.ItemArray(col))
            Next
            SqlContext.Pipe.SendResultsRow(record)
        Next
    End Sub

    Private Shared Function GetServerResults(ByVal ServerName As String, _
                                            ByVal AuthenticationMethod As AutheticationMethods, _
                                            ByVal Database As String, _
                                            ByVal Command As String, _
                                            ByVal IsResultExpected As Boolean, _
                                            ByRef Record As SqlDataRecord, _
                                            ByVal SqlLogin As String, _
                                            ByVal SqlPassword As String, _
                                            ByVal OutputTable As String, _
                                            ByRef dtServerResults As DataTable) As Integer
        Dim cs As String
        'SqlContext.Pipe.Send(ServerName)
        cs = BuildConnectionString(ServerName, _
                                    AuthenticationMethod, _
                                    SqlLogin, _
                                    SqlPassword, _
                                    Database)
        Dim Con As SqlConnection = New SqlConnection(cs)
        Dim da As SqlDataAdapter
        Dim cmd As New SqlCommand
        Dim dt As New DataTable
        Dim dt1 As DataTable
        Dim RecordsAffected As Integer
        cmd.Connection = Con
        cmd.CommandTimeout = 0
        cmd.CommandType = CommandType.Text
        cmd.CommandText = Command
        Con.Open()
        If IsResultExpected Then
            da = New SqlDataAdapter(cmd)
            If Record Is Nothing And OutputTable = "" Then
                dt = New DataTable("Results")
                Try
                    da.FillSchema(dt, SchemaType.Source)
                    Record = New SqlDataRecord(GetTableSchema(dt).ToArray())
                    If Record.FieldCount = 0 Then
                        Record = Nothing
                    Else
                        SqlContext.Pipe.SendResultsStart(Record)
                    End If
                Catch
                End Try
            End If
            da.Fill(dt)
            RecordsAffected = dt.Rows.Count
            Con.Close()
            If OutputTable = "" Then
                If Record Is Nothing Then
                    Record = New SqlDataRecord(GetTableSchema(dt).ToArray())
                    SqlContext.Pipe.SendResultsStart(Record)
                End If
                Try
                    SendDataTableOverPipe(dt, Record)
                Catch
                    dt1 = dt.Clone
                    For Each dc As DataColumn In dt1.Columns
                        If dc.DataType.ToString = "System.Int32" Then
                            dc.DataType = GetType(System.Int64)
                        End If
                    Next
                    For Each dr As DataRow In dt.Rows
                        dt1.ImportRow(dr)
                    Next
                    SendDataTableOverPipe(dt1, Record)
                End Try
            Else
                dtServerResults = dt
            End If
        Else
            RecordsAffected = cmd.ExecuteNonQuery()
        End If
        Return RecordsAffected
    End Function

    Private Shared Function RunThroughServers(ByVal RUN_ID As Integer, _
                                                ByVal ServersTable As DataTable, _
                                                ByVal Database As String, _
                                                ByVal Command As String, _
                                                ByVal IsResultExpected As Boolean, _
                                                ByVal LogToDB As Boolean, _
                                                ByVal SqlLogin As String, _
                                                ByVal SqlPassword As String, _
                                                ByVal OutputTable As String, _
                                                ByRef TotalRows As Integer) As Integer
        Dim LocalCon As SqlConnection = New SqlConnection(m_ConString)
        Dim daStart As SqlDataAdapter
        Dim cmdStart As New SqlCommand
        Dim cmdEnd As New SqlCommand
        Dim dtServers As New DataTable
        Dim dtTemp As New DataTable
        Dim SRR_ID As Integer = 0
        Dim Record As SqlDataRecord
        Dim NumOfErrors As Integer
        Dim RecordsAffected As Integer
        Dim dtServerResults As DataTable
        Dim dtWriteToDB As New DataTable
        Dim Exp As Exception
        Dim cmdTab As New SqlCommand
        Dim daTab As SqlDataAdapter

        Try
            LocalCon.Open()
            If LogToDB Then
                With cmdStart
                    .Connection = LocalCon
                    .CommandTimeout = 0
                    .CommandType = CommandType.StoredProcedure
                    .CommandText = "SYL.usp_StartServerRun"
                    .Parameters.Add("@RUN_ID", SqlDbType.Int)
                    .Parameters("@RUN_ID").Value = RUN_ID
                    .Parameters.Add("@ServerName", SqlDbType.NVarChar, 255)
                End With
                daStart = New SqlDataAdapter(cmdStart)
                With cmdEnd
                    .Connection = LocalCon
                    .CommandTimeout = 0
                    .CommandType = CommandType.StoredProcedure
                    .CommandText = "SYL.usp_EndServerRun"
                    .Parameters.Add("@SRR_ID", SqlDbType.Int)
                    .Parameters.Add("@RecordsAffected", SqlDbType.Int)
                    .Parameters.Add("@ErrorMessage", SqlDbType.VarChar, -1)
                End With
            End If
            For Each row As DataRow In ServersTable.Rows
                Try
                    If LogToDB Then
                        RecordsAffected = 0
                        cmdStart.Parameters("@ServerName").Value = row.Item("ServerName").ToString
                        daStart.Fill(dtTemp)
                        SRR_ID = CType(dtTemp.Rows(0).Item("SRR_ID"), Integer)
                        dtTemp.Dispose()
                        dtTemp = New DataTable
                        'SqlContext.Pipe.Send("Start - " & row.Item("ServerName").ToString & " - " & SRR_ID.ToString)
                    End If
                    RecordsAffected = GetServerResults(row.Item("ServerName").ToString, _
                                                        CType(row.Item("IsWindowsAuthentication"), AutheticationMethods), _
                                                        Database, _
                                                        Command, _
                                                        IsResultExpected, _
                                                        Record, _
                                                        SqlLogin, _
                                                        SqlPassword, _
                                                        OutputTable, _
                                                        dtServerResults)
                    TotalRows += RecordsAffected
                    If OutputTable <> "" Then
                        If dtWriteToDB.Rows.Count = 0 Then
                            With cmdTab
                                .Connection = LocalCon
                                .CommandTimeout = 0
                                .CommandType = CommandType.Text
                                .CommandText = "SELECT * FROM [" + OutputTable + "]"
                            End With
                            daTab = New SqlDataAdapter(cmdTab)
                            daTab.FillSchema(dtWriteToDB, SchemaType.Source)
                        End If
                        For Each dr As DataRow In dtServerResults.Rows
                            dtWriteToDB.ImportRow(dr)
                        Next
                    End If
                Catch Exp
                    NumOfErrors += NumOfErrors
                Finally
                    'SqlContext.Pipe.Send("End - " & row.Item("ServerName").ToString & " - " & SRR_ID.ToString)
                    If SRR_ID <> 0 Then
                        With cmdEnd
                            .Parameters("@SRR_ID").Value = SRR_ID
                            .Parameters("@RecordsAffected").Value = RecordsAffected
                            If Exp Is Nothing Then
                                .Parameters("@ErrorMessage").Value = DBNull.Value
                            Else
                                .Parameters("@ErrorMessage").Value = Exp.Message
                                NumOfErrors += 1
                                Exp = Nothing
                            End If
                            .ExecuteNonQuery()
                        End With
                        SRR_ID = 0
                    ElseIf Not Exp Is Nothing Then
                        Throw Exp
                    End If
                End Try
            Next row
            If IsResultExpected And SqlContext.Pipe.IsSendingResults Then
                SqlContext.Pipe.SendResultsEnd()
            End If
        Finally
            If Exp Is Nothing And OutputTable <> "" Then
                For Each dr As DataRow In dtWriteToDB.Rows
                    dr.SetAdded()
                Next
                Dim cb As New SqlCommandBuilder(daTab)
                daTab.Update(dtWriteToDB)
                daTab.Dispose()
            End If
            If Not LocalCon Is Nothing Then
                If LocalCon.State <> ConnectionState.Closed Then
                    LocalCon.Close()
                End If
                LocalCon.Dispose()
            End If
            If Not cmdStart Is Nothing Then cmdStart.Dispose()
            If Not cmdEnd Is Nothing Then cmdEnd.Dispose()
            If Not daStart Is Nothing Then daStart.Dispose()
            If Not dtWriteToDB Is Nothing Then dtWriteToDB = Nothing
            If cmdTab Is Nothing Then cmdTab = Nothing
            If daTab Is Nothing Then daTab = Nothing
            If Not Exp Is Nothing Then
                Throw Exp
            End If
        End Try
        Return NumOfErrors
    End Function

    Public Shared Function udf_EncryptPassword(ByVal sqlPassword As String) As String
        Return Encrypt(sqlPassword, "&%#@?,:*")
    End Function

    Private Shared Function DecryptPassword(ByVal EncryptedPassword As String) As String
        Return Decrypt(EncryptedPassword, "&%#@?,:*")
    End Function

    Private Shared Function Encrypt(ByVal strText As String, ByVal strEncrKey _
             As String) As String
        Dim byKey() As Byte = {}
        Dim IV() As Byte = {&H12, &H34, &H56, &H78, &H90, &HAB, &HCD, &HEF}

        Try
            byKey = System.Text.Encoding.UTF8.GetBytes(Left(strEncrKey, 8))

            Dim des As New DESCryptoServiceProvider()
            Dim inputByteArray() As Byte = Encoding.UTF8.GetBytes(strText)
            Dim ms As New MemoryStream()
            Dim cs As New CryptoStream(ms, des.CreateEncryptor(byKey, IV), CryptoStreamMode.Write)
            cs.Write(inputByteArray, 0, inputByteArray.Length)
            cs.FlushFinalBlock()
            Return Convert.ToBase64String(ms.ToArray())

        Catch ex As Exception
            Return ex.Message
        End Try

    End Function

    Private Shared Function Decrypt(ByVal strText As String, ByVal sDecrKey _
               As String) As String
        Dim byKey() As Byte = {}
        Dim IV() As Byte = {&H12, &H34, &H56, &H78, &H90, &HAB, &HCD, &HEF}
        Dim inputByteArray(strText.Length) As Byte

        Try
            byKey = System.Text.Encoding.UTF8.GetBytes(Left(sDecrKey, 8))
            Dim des As New DESCryptoServiceProvider()
            inputByteArray = Convert.FromBase64String(strText)
            Dim ms As New MemoryStream()
            Dim cs As New CryptoStream(ms, des.CreateDecryptor(byKey, IV), CryptoStreamMode.Write)

            cs.Write(inputByteArray, 0, inputByteArray.Length)
            cs.FlushFinalBlock()
            Dim encoding As System.Text.Encoding = System.Text.Encoding.UTF8

            Return encoding.GetString(ms.ToArray())

        Catch ex As Exception
            Return ex.Message
        End Try

    End Function

    Public Shared Sub usp_RunCommand(ByVal ServerList As String, _
                                    ByVal Database As String, _
                                    ByVal Command As String, _
                                    Optional ByVal IsResultExpected As Boolean = True, _
                                    Optional ByVal LogToDB As Boolean = False, _
                                    Optional ByVal SqlLogin As String = "", _
                                    Optional ByVal SqlPassword As String = "", _
                                    Optional ByVal OutputTable As String = "", _
                                    Optional ByVal Identifier As Integer = 0)

        Dim LocalCon As SqlConnection = New SqlConnection(m_ConString)
        Dim da As SqlDataAdapter
        Dim cmd As New SqlCommand
        Dim dtServers As New DataTable
        Dim dtTemp As New DataTable
        Dim RUN_ID As Integer = 0
        Dim NumOfErrors As Integer = 0
        Dim Exp As Exception
        Dim Arr() As String
        Dim HaveSqlAuthentication As Boolean
        Dim TotalRows As Integer
        Try
            If LogToDB Then
                LocalCon.Open()
                With cmd
                    .Connection = LocalCon
                    .CommandTimeout = 0
                    .CommandType = CommandType.StoredProcedure
                    .CommandText = "SYL.usp_GetServersList"
                    .Parameters.AddWithValue("@ServerList", ServerList)
                    da = New SqlDataAdapter(cmd)
                    da.Fill(dtServers)
                    For Each dr As DataRow In dtServers.Rows
                        If CType(dr.Item("IsWindowsAuthentication"), Boolean) = False Then
                            HaveSqlAuthentication = True
                            Exit For
                        End If
                    Next
                    .CommandText = "SYL.usp_StartRun"
                    .Parameters.AddWithValue("@Database", Database)
                    .Parameters.AddWithValue("@Command", Command)
                    .Parameters.AddWithValue("@ExpectsResults", IsResultExpected)
                    .Parameters.AddWithValue("@Identifier", Identifier)
                End With
                da = New SqlDataAdapter(cmd)
                da.Fill(dtTemp)
                RUN_ID = CType(dtTemp.Rows(0).Item("RUN_ID"), Integer)
                If HaveSqlAuthentication And SqlPassword = "" Then
                    dtTemp = Nothing
                    dtTemp = New DataTable
                    With cmd
                        .CommandText = "SYL.usp_RetrieveLoginDetails"
                        .Parameters.Clear()
                        .Parameters.Add("@SqlLogin", SqlDbType.NVarChar, 255)
                        .Parameters("@SqlLogin").Value = SqlLogin
                    End With
                    da = New SqlDataAdapter(cmd)
                    da.Fill(dtTemp)
                    SqlLogin = CType(dtTemp.Rows(0).Item("SqlLogin"), String)
                    SqlPassword = DecryptPassword(CType(dtTemp.Rows(0).Item("SqlPassword"), String))
                End If
                LocalCon.Close()
            Else
                dtServers.Columns.Add("ServerName", GetType(String))
                dtServers.Columns.Add("IsWindowsAuthentication", GetType(Boolean))
                Arr = Split(ServerList, ",")
                For Each str As String In Arr
                    dtServers.Rows.Add(str, (SqlLogin = ""))
                Next
            End If
            NumOfErrors = RunThroughServers(RUN_ID, _
                                            dtServers, _
                                            Database, _
                                            Command, _
                                            IsResultExpected, _
                                            LogToDB, _
                                            SqlLogin, _
                                            SqlPassword, _
                                            OutputTable, _
                                            TotalRows)
        Catch Exp
            NumOfErrors += 1
            Throw Exp
        Finally
            If Exp Is Nothing And (Not IsResultExpected Or OutputTable <> "") Then 'if nocount is off print "row(s) affected"
                If LocalCon.State <> ConnectionState.Open Then
                    LocalCon.Open()
                End If
                With cmd
                    .Connection = LocalCon
                    .CommandTimeout = 0
                    .CommandType = CommandType.Text
                    .Parameters.Clear()
                    .CommandText = "create table #Settings(Setting nvarchar(500), Val sql_variant) " & _
                                    "insert into #Settings " & _
                                    "exec sp_executesql N'DBCC USEROPTIONS WITH NO_INFOMSGS' " & _
                                    "select isnull((select top 1 1 " & _
                                                    "from #Settings " & _
                                                    "where Setting = 'nocount' and Val = 'SET'), 0) Result " & _
                                    "drop table #Settings"
                End With
                da = New SqlDataAdapter(cmd)
                dtTemp = New DataTable
                da.Fill(dtTemp)
                If CType(dtTemp.Rows(0).Item("Result"), Integer) = 0 Then
                    If TotalRows >= 0 Then
                        SqlContext.Pipe.Send("(" + TotalRows.ToString + " row(s) affected)")
                    Else
                        SqlContext.Pipe.Send("Command ran on " + (-TotalRows).ToString + " server(s)")
                    End If
                End If
            End If
            If RUN_ID <> 0 Then
                If LocalCon.State <> ConnectionState.Closed Then
                    LocalCon.Close()
                End If
                LocalCon.Open()
                With cmd
                    cmd = New SqlCommand
                    .Connection = LocalCon
                    .CommandTimeout = 0
                    .CommandType = CommandType.StoredProcedure
                    .CommandText = "SYL.usp_EndRun"
                    .Parameters.Clear()
                    .Parameters.AddWithValue("@RUN_ID", RUN_ID)
                    .Parameters.AddWithValue("@NumberOfErrors", NumOfErrors)
                    If Not Exp Is Nothing Then
                        .Parameters.AddWithValue("@ErrorMessage", Exp.Message)
                    End If
                    .ExecuteNonQuery()
                End With
                LocalCon.Close()
            End If
            If Not LocalCon Is Nothing Then
                If LocalCon.State <> ConnectionState.Closed Then
                    LocalCon.Close()
                End If
                LocalCon.Dispose()
            End If
            If Not cmd Is Nothing Then cmd.Dispose()
            If Not da Is Nothing Then da.Dispose()
            If Not dtServers Is Nothing Then dtServers.Dispose()
            If Not dtTemp Is Nothing Then dtTemp.Dispose()
        End Try
    End Sub
End Class
